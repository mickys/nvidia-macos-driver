# mickys overlay (install.sh --cli-aliases): these tools run through nvenc-run, so they see the NVENC encoder.
# Sourced by /etc/zshrc and /etc/bashrc (interactive shells). Bypass once with `command ffmpeg ...`.
function ffmpeg { /usr/local/bin/nvenc-run ffmpeg "$@"; }
function HandBrakeCLI { /usr/local/bin/nvenc-run HandBrakeCLI "$@"; }
function avconvert { /usr/local/bin/nvenc-run avconvert "$@"; }
