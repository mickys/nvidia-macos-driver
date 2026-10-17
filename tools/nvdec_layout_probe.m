// nvdec_layout_probe.m: measure the pixel mapping between the Blackwell ("bw8/bw16") and classic ("t2d") layouts on a
// pre-Blackwell GPU, using nullmoth's decoder libraries. H.264 decoding is bit-exact, so a decoder that untiles in the
// wrong layout returns a pure permutation of Apple's software decode of the same bitstream.
//   clang -fobjc-arc -O2 -o nvdec_layout_probe nvdec_layout_probe.m -framework VideoToolbox -framework CoreMedia \
//         -framework CoreVideo -framework Foundation
//   ./nvdec_layout_probe W H LIB OUT      LIB = libnvdec_h264.dylib (Blackwell untile) or libnvdec_h264_t2d.dylib (classic)
// Writes OUT.src.yuv (the NV12 frame encoded), OUT.sw.yuv (Apple's decode), OUT.hw.yuv (the library's decode); each is
// W*H luma + W*H/2 interleaved chroma, tightly packed.
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>

static int W, H;

static void write_nv12(CVPixelBufferRef pb, const char *path)
{
    FILE *f = fopen(path, "wb"); if (!f) { perror(path); return; }
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    for (int p = 0; p < 2; p++) {
        const uint8_t *b = CVPixelBufferGetBaseAddressOfPlane(pb, p); size_t s = CVPixelBufferGetBytesPerRowOfPlane(pb, p);
        for (int r = 0; r < (p ? H / 2 : H); r++) fwrite(b + r * s, 1, W, f);
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); fclose(f);
}

static CVPixelBufferRef decode(CMSampleBufferRef sb, bool hw)
{
    NSDictionary *spec = hw ? @{ (__bridge NSString *)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: @YES }
                            : @{ (__bridge NSString *)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: @NO };
    NSDictionary *attr = @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
    VTDecompressionSessionRef d = NULL;
    OSStatus st = VTDecompressionSessionCreate(NULL, CMSampleBufferGetFormatDescription(sb), (__bridge CFDictionaryRef)spec,
                                               (__bridge CFDictionaryRef)attr, NULL, &d);
    if (st) { printf("%s decoder: create -> %d\n", hw ? "hw" : "sw", (int)st); return NULL; }
    __block CVPixelBufferRef out = NULL;
    st = VTDecompressionSessionDecodeFrameWithOutputHandler(d, sb, 0, NULL,
        ^(OSStatus s, VTDecodeInfoFlags fl, CVImageBufferRef img, CMTime pts, CMTime dur) { if (!s && img) out = CVPixelBufferRetain(img); else printf("decode status %d\n", (int)s); });
    VTDecompressionSessionWaitForAsynchronousFrames(d);
    CFBooleanRef usingHw = NULL; VTSessionCopyProperty(d, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &usingHw);
    printf("%s decoder: frame %s, hardware=%s\n", hw ? "hw" : "sw", out ? "ok" : "MISSING", usingHw == kCFBooleanTrue ? "yes" : "no");
    VTDecompressionSessionInvalidate(d); CFRelease(d);
    return out;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 5) { fprintf(stderr, "usage: nvdec_layout_probe W H LIB OUT\n"); return 2; }
    W = atoi(argv[1]); H = atoi(argv[2]); const char *lib = argv[3], *out = argv[4];

    char path[1024];
    snprintf(path, sizeof path, "/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/%s", lib);
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("dlopen %s: %s\n", path, dlerror()); return 1; }
    void *fac = dlsym(h, "NVDecH264_CreateInstance");
    typedef int32_t (*RegFn)(uint32_t, CFDictionaryRef, void *);
    RegFn reg = (RegFn)dlsym(RTLD_DEFAULT, "VTRegisterVideoDecoderWithInfo");
    if (!fac || !reg) { printf("factory %p reg %p\n", fac, reg); return 1; }
    NSDictionary *info = @{ @"CMClassImplementationID": @"probe.nvdec.avc", @"VTRating": @1000, @"VTIsHardwareAccelerated": @YES };
    printf("registered %s -> %d\n", lib, (int)reg('avc1', (__bridge CFDictionaryRef)info, fac));

    // source: random luma/chroma (unique-looking byte runs), so every small run of the output can be found in the source
    NSDictionary *pbAttr = @{ (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    CVPixelBufferRef src = NULL;
    CVPixelBufferCreate(NULL, W, H, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef)pbAttr, &src);
    CVPixelBufferLockBaseAddress(src, 0);
    srandom(12345);
    for (int p = 0; p < 2; p++) {
        uint8_t *b = CVPixelBufferGetBaseAddressOfPlane(src, p); size_t s = CVPixelBufferGetBytesPerRowOfPlane(src, p);
        for (int r = 0; r < (p ? H / 2 : H); r++) for (int c = 0; c < W; c++) b[r * s + c] = (uint8_t)(16 + random() % 220);
    }
    CVPixelBufferUnlockBaseAddress(src, 0);
    snprintf(path, sizeof path, "%s.src.yuv", out); write_nv12(src, path);

    // one IDR frame with Apple's software encoder (the content only has to be identical for both decoders)
    NSDictionary *espec = @{ (__bridge NSString *)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @NO };
    VTCompressionSessionRef enc = NULL;
    OSStatus st = VTCompressionSessionCreate(NULL, W, H, kCMVideoCodecType_H264, (__bridge CFDictionaryRef)espec, NULL, NULL, NULL, NULL, &enc);
    if (st) { printf("encoder create -> %d\n", (int)st); return 1; }
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(200000000));
    __block CMSampleBufferRef sb = NULL;
    VTCompressionSessionEncodeFrameWithOutputHandler(enc, src, CMTimeMake(0, 60), CMTimeMake(1, 60), NULL, NULL,
        ^(OSStatus s, VTEncodeInfoFlags fl, CMSampleBufferRef b) { if (!s && b) sb = (CMSampleBufferRef)CFRetain(b); });
    VTCompressionSessionCompleteFrames(enc, kCMTimeInvalid);
    VTCompressionSessionInvalidate(enc); CFRelease(enc);
    if (!sb) { printf("no encoded frame\n"); return 1; }
    printf("encoded %zu bytes\n", CMSampleBufferGetTotalSampleSize(sb));

    CVPixelBufferRef sw = decode(sb, false), hw = decode(sb, true);
    if (sw) { snprintf(path, sizeof path, "%s.sw.yuv", out); write_nv12(sw, path); }
    if (hw) { snprintf(path, sizeof path, "%s.hw.yuv", out); write_nv12(hw, path); }
    return (sw && hw) ? 0 : 1;
} }
