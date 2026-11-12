# HDR test bench

Tools used to build and verify HDR video on Windows: Chudder on a Flutter
engine with HDR support (`C:\src\flutter`, branch `hdr-engine`) and a
media_kit_video with HDR output (`../media-kit-hdr`, branch `hdr`).

Ordinary screenshots (gdigrab, PrintWindow) cannot judge HDR: Windows maps an
HDR window's scRGB 1.0 (80 nits) to white for them, so HDR content looks
over-bright and everything above clips. `hdrcap` captures through
Windows.Graphics.Capture in 16-bit float instead - the composed picture in
scRGB, as the display gets it.

| File | What it is |
| --- | --- |
| `render_probe.dart` | Fixed UI scene (gradients, blur, text, an extended-sRGB 4.0 patch) for engine-vs-engine comparisons |
| `video_probe.dart` | media_kit video under opaque bars; `h` switches window + output HDR |
| `libmpv_probe.dart` | Chudder's own `LibMPV` over local files; `n` opens the next |
| `build_variant.sh` | `build_variant.sh <entry> <name> [local]` - stock or local-engine build into `builds/<name>` |
| `capture.ps1` | Fixed 1600x900 window, gdigrab PNG and optional float capture |
| `toggle.ps1`, `libmpv_run.ps1` | Float captures across HDR on/off switches |
| `hdrcap/` | The float capture tool (`build.cmd` compiles it) |
| `f16.py`, `compare.py`, `gain.py`, `f16_where.py` | Statistics on captures |

Test media are generated with ffmpeg (not committed):

```
ffmpeg -f lavfi -i "testsrc2=s=1920x1080:r=30,format=gbrpf32le" -t 60 \
  -vf "zscale=tin=bt709:pin=bt709:min=gbr:rin=pc:t=smpte2084:p=bt2020:m=bt2020nc:r=tv:npl=1000,format=yuv420p10le" \
  -c:v libx265 -preset ultrafast -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1" hdr10_test.mkv
ffmpeg -f lavfi -i "testsrc2=s=1920x1080:r=30" -t 60 -c:v libx264 -crf 23 -pix_fmt yuv420p sdr_test.mkv
```

The HDR clip maps the test pattern's white to 1000 nits, so its primaries
should land near 12.5 in scRGB (1000/80) on a display that reaches 1000 nits.
