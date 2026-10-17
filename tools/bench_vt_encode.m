// bench_vt_encode.m: encode synthetic NV12 frames with VideoToolbox, decode them with Apple's software decoder, report luma
// PSNR against the source. Shows which encoder VideoToolbox picked (nullmoth's NVENC or Apple's).
//   clang -fobjc-arc -O2 -o bench_vt_encode bench_vt_encode.m -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
//         -framework Metal -framework Foundation -framework IOSurface
//   ./bench_vt_encode [hw|sw] [avc1|hvc1] [W H FRAMES] [dump.ppm]
// hw = RequireHardwareAcceleratedVideoEncoder (fails instead of falling back), sw = Apple's software encoder.
// A Metal device is created first: nullmoth's plugin registers its encoders with VideoToolbox when one comes up.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#include <math.h>
#include <mach/mach_time.h>

static int W = 1920, H = 1080, N = 60;

static void fill(CVPixelBufferRef pb, int f)
{
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
    size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
    for (int r = 0; r < H; r++)
        for (int c = 0; c < W; c++) {
            // moving diagonal gradient + 64 px checkerboard + a sweeping bar: easy to recognize when torn
            int v = ((c + r + f * 8) & 255) / 2 + ((((c >> 6) ^ (r >> 6)) & 1) ? 90 : 0);
            if (abs(c - (f * 24) % W) < 16) v = 235;
            y[r * ys + c] = (uint8_t)(16 + v * 219 / 255);
        }
    for (int r = 0; r < H / 2; r++)
        for (int c = 0; c < W / 2; c++) {
            uv[r * uvs + 2 * c] = (uint8_t)(128 + 60 * sin((c + f) * 0.02));
            uv[r * uvs + 2 * c + 1] = (uint8_t)(128 + 60 * cos((r + f) * 0.02));
        }
    CVPixelBufferUnlockBaseAddress(pb, 0);
}

// VT_PRESWIZZLE=1: hand the encoder library a frame pre-arranged so that its Blackwell tiling, read back by a
// pre-Blackwell NVENC as classic block-linear, gives the original picture: in[p] = img[P(p)], where P is the per-tile
// mapping measured with nvdec_layout_probe.m (64-byte x 8-row tiles, 8-byte chunks; luma and chroma differ).
static inline void src_of(int plane, int r, int j, int *sr, int *sc)
{
    if (plane == 0) { *sr = (r >> 1) + 4 * ((j >> 1) & 1); *sc = 8 * (r & 1) + 16 * (j & 1) + 32 * (j >> 2); }
    else            { *sr = (r & 3) + 4 * ((j >> 1) & 1);  *sc = 8 * (j & 1) + 16 * ((r >> 2) & 1) + 32 * (j >> 2); }
}
static void preswizzle(CVPixelBufferRef src, CVPixelBufferRef dst)
{
    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly); CVPixelBufferLockBaseAddress(dst, 0);
    for (int p = 0; p < 2; p++) {
        const uint8_t *s = CVPixelBufferGetBaseAddressOfPlane(src, p); uint8_t *d = CVPixelBufferGetBaseAddressOfPlane(dst, p);
        size_t ss = CVPixelBufferGetBytesPerRowOfPlane(src, p), ds = CVPixelBufferGetBytesPerRowOfPlane(dst, p);
        int rows = p ? H / 2 : H;
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < W; c += 8) {
                int sr, sc; src_of(p, r & 7, (c & 63) >> 3, &sr, &sc);
                sr += r & ~7; sc += c & ~63;
                if (sr >= rows) sr = rows - 1;           // partial last tile: no source row, repeat the edge
                int n = W - c < 8 ? W - c : 8;
                if (sc + n > W) { memset(d + r * ds + c, 128, n); continue; }
                memcpy(d + r * ds + c, s + sr * ss + sc, n);
            }
    }
    CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly); CVPixelBufferUnlockBaseAddress(dst, 0);
}

static double psnr_luma(CVPixelBufferRef a, CVPixelBufferRef b)
{
    CVPixelBufferLockBaseAddress(a, kCVPixelBufferLock_ReadOnly); CVPixelBufferLockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    const uint8_t *pa = CVPixelBufferGetBaseAddressOfPlane(a, 0), *pb = CVPixelBufferGetBaseAddressOfPlane(b, 0);
    size_t sa = CVPixelBufferGetBytesPerRowOfPlane(a, 0), sb = CVPixelBufferGetBytesPerRowOfPlane(b, 0);
    double se = 0;
    for (int r = 0; r < H; r++) for (int c = 0; c < W; c++) { double d = (double)pa[r * sa + c] - pb[r * sb + c]; se += d * d; }
    CVPixelBufferUnlockBaseAddress(a, kCVPixelBufferLock_ReadOnly); CVPixelBufferUnlockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    double mse = se / ((double)W * H);
    return mse == 0 ? 99.0 : 10 * log10(255.0 * 255.0 / mse);
}

static double psnr_chroma(CVPixelBufferRef a, CVPixelBufferRef b, int lastRows)
{
    // lastRows > 0: only the bottom lastRows chroma rows (where a partial 8-row tile would show up)
    CVPixelBufferLockBaseAddress(a, kCVPixelBufferLock_ReadOnly); CVPixelBufferLockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    const uint8_t *pa = CVPixelBufferGetBaseAddressOfPlane(a, 1), *pb = CVPixelBufferGetBaseAddressOfPlane(b, 1);
    size_t sa = CVPixelBufferGetBytesPerRowOfPlane(a, 1), sb = CVPixelBufferGetBytesPerRowOfPlane(b, 1);
    int r0 = lastRows > 0 ? H / 2 - lastRows : 0; double se = 0; long n = 0;
    for (int r = r0; r < H / 2; r++) for (int c = 0; c < W; c++) { double d = (double)pa[r * sa + c] - pb[r * sb + c]; se += d * d; n++; }
    CVPixelBufferUnlockBaseAddress(a, kCVPixelBufferLock_ReadOnly); CVPixelBufferUnlockBaseAddress(b, kCVPixelBufferLock_ReadOnly);
    double mse = se / n; return mse == 0 ? 99.0 : 10 * log10(255.0 * 255.0 / mse);
}

static void dump_luma(CVPixelBufferRef pb, const char *path)
{
    FILE *f = fopen(path, "wb"); if (!f) return;
    fprintf(f, "P5 %d %d 255\n", W, H);
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const uint8_t *p = CVPixelBufferGetBaseAddressOfPlane(pb, 0); size_t s = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
    for (int r = 0; r < H; r++) fwrite(p + r * s, 1, W, f);
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); fclose(f);
}

int main(int argc, char **argv) { @autoreleasepool {
    bool hw = argc < 2 || strcmp(argv[1], "sw");
    CMVideoCodecType codec = (argc > 2 && !strcmp(argv[2], "hvc1")) ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264;
    if (argc > 5) { W = atoi(argv[3]); H = atoi(argv[4]); N = atoi(argv[5]); }
    const char *dump = argc > 6 ? argv[6] : NULL;

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    printf("metal: %s\n", dev ? dev.name.UTF8String : "(none)");

    CFArrayRef list = NULL; VTCopyVideoEncoderList(NULL, &list);
    for (NSDictionary *e in (__bridge NSArray *)list) {
        NSString *eid = e[(__bridge NSString *)kVTVideoEncoderList_EncoderID];
        if ([eid containsString:@"nvmtl"] || [eid containsString:@"nvenc"])
            printf("registered: %s (%s) hw=%s\n", eid.UTF8String, [e[(__bridge NSString *)kVTVideoEncoderList_EncoderName] UTF8String],
                   [e[(__bridge NSString *)kVTVideoEncoderList_IsHardwareAccelerated] boolValue] ? "yes" : "no");
    }
    if (list) CFRelease(list);

    NSMutableDictionary *spec = [(hw ? @{ (__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES }
                                     : @{ (__bridge NSString *)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @NO }) mutableCopy];
    // VT_LOWLAT=1: ask for low-latency rate control, as streaming hosts (Parsec) do
    if (getenv("VT_LOWLAT")) spec[(__bridge NSString *)kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = @YES;
    if (getenv("VT_LOWLAT")) printf("spec: EnableLowLatencyRateControl\n");
    NSDictionary *pbAttr = @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                              (__bridge NSString *)kCVPixelBufferWidthKey: @(W), (__bridge NSString *)kCVPixelBufferHeightKey: @(H),
                              (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{} };

    NSMutableArray *encoded = [NSMutableArray array];
    __block size_t bytes = 0; __block int errors = 0;
    VTCompressionSessionRef enc = NULL;
    OSStatus st = VTCompressionSessionCreate(NULL, W, H, codec, (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)pbAttr, NULL, NULL, NULL, &enc);
    if (st) { printf("RESULT encoder=none create_status=%d\n", (int)st); return 1; }
    CFStringRef encId = NULL; VTSessionCopyProperty(enc, kVTCompressionPropertyKey_EncoderID, NULL, &encId);
    CFBooleanRef usingHw = NULL; VTSessionCopyProperty(enc, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &usingHw);
    printf("encoder: %s hardware=%s\n", encId ? [(__bridge NSString *)encId UTF8String] : "?", usingHw == kCFBooleanTrue ? "yes" : "no");
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(20000000));
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(60));

    NSMutableArray *sources = [NSMutableArray array];
    uint64_t t0 = mach_absolute_time();
    for (int f = 0; f < N; f++) {
        CVPixelBufferRef pb = NULL;
        CVPixelBufferCreate(NULL, W, H, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef)pbAttr, &pb);
        fill(pb, f);
        [sources addObject:(__bridge id)pb];
        CVPixelBufferRef in = pb;
        if (getenv("VT_PRESWIZZLE")) {
            CVPixelBufferCreate(NULL, W, H, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef)pbAttr, &in);
            preswizzle(pb, in);
        }
        st = VTCompressionSessionEncodeFrameWithOutputHandler(enc, in, CMTimeMake(f, 60), CMTimeMake(1, 60), NULL, NULL,
            ^(OSStatus s, VTEncodeInfoFlags fl, CMSampleBufferRef sb) {
                if (s || !sb) { errors++; return; }
                bytes += CMSampleBufferGetTotalSampleSize(sb);
                @synchronized (encoded) { [encoded addObject:(__bridge id)sb]; }
            });
        if (in != pb) CVPixelBufferRelease(in);
        CVPixelBufferRelease(pb);
        if (st) { printf("encode frame %d -> %d\n", f, (int)st); errors++; break; }
    }
    VTCompressionSessionCompleteFrames(enc, kCMTimeInvalid);
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double secs = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e9;
    VTCompressionSessionInvalidate(enc); CFRelease(enc);
    printf("encoded: %lu of %d frames, %zu bytes (%.1f Mbit/s at 60 fps), %d errors, %.1f fps\n", (unsigned long)encoded.count, N,
           bytes, encoded.count ? bytes * 8.0 * 60 / encoded.count / 1e6 : 0, errors, N / secs);
    if (!encoded.count) { printf("RESULT encoder=%s frames=0\n", encId ? [(__bridge NSString *)encId UTF8String] : "?"); return 1; }

    // decode with Apple's software decoder, compare luma with the source frame of the same timestamp
    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription((__bridge CMSampleBufferRef)encoded[0]);
    NSDictionary *dspec = @{ (__bridge NSString *)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: @NO };
    NSDictionary *dattr = @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
    VTDecompressionSessionRef dec = NULL;
    st = VTDecompressionSessionCreate(NULL, fmt, (__bridge CFDictionaryRef)dspec, (__bridge CFDictionaryRef)dattr, NULL, &dec);
    if (st) { printf("decoder create -> %d\n", (int)st); return 1; }
    __block double sum = 0, minp = 1e9, csum = 0, cmin = 1e9, esum = 0; __block int decoded = 0, derr = 0;
    for (id o in encoded) {
        CMSampleBufferRef sb = (__bridge CMSampleBufferRef)o;
        int idx = (int)llround(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) * 60);
        VTDecompressionSessionDecodeFrameWithOutputHandler(dec, sb, 0, NULL,
            ^(OSStatus s, VTDecodeInfoFlags fl, CVImageBufferRef img, CMTime pts, CMTime dur) {
                if (s || !img) { derr++; return; }
                double p = psnr_luma((__bridge CVPixelBufferRef)sources[idx], img);
                sum += p; if (p < minp) minp = p; decoded++;
                double cp = psnr_chroma((__bridge CVPixelBufferRef)sources[idx], img, 0); csum += cp; if (cp < cmin) cmin = cp;
                esum += psnr_chroma((__bridge CVPixelBufferRef)sources[idx], img, 8);
                if (dump && idx == N / 2) { dump_luma(img, dump); }
            });
    }
    VTDecompressionSessionWaitForAsynchronousFrames(dec);
    VTDecompressionSessionInvalidate(dec); CFRelease(dec);
    printf("chroma: psnr_avg=%.2f psnr_min=%.2f, bottom 8 chroma rows avg=%.2f\n", decoded ? csum / decoded : 0, decoded ? cmin : 0, decoded ? esum / decoded : 0);
    printf("RESULT encoder=%s hw=%s frames=%lu decoded=%d decode_errors=%d psnr_avg=%.2f psnr_min=%.2f\n",
           encId ? [(__bridge NSString *)encId UTF8String] : "?", usingHw == kCFBooleanTrue ? "yes" : "no",
           (unsigned long)encoded.count, decoded, derr, decoded ? sum / decoded : 0, decoded ? minp : 0);
    return 0;
} }
