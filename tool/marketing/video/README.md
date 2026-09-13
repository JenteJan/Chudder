# Showcase video

`assets/marketing/chudder_showcase.mp4` is rendered frame by frame with PIL and muxed with ffmpeg.
Footage, music and renders live in `../out/` (gitignored); only these scripts are kept.

The renderer is layered, each file patching the one before it:

- `render7.py` - the base: timing helpers, background, device frames (phone, tablet, monitor, TV),
  the drop shot with the magnified "Direct · SDR 4K" badge, and the cast shot.
- `render8.py` - 60 fps, drop on bar 3, the opener that pulls back from the film into the TV,
  push transitions, the SyncPlay arc, the recap tiles and the outro.
- `render10.py` - the current cut: take geometry and timings for the 2026-09-13 footage, and the
  shot list. v9 was the same cut on older footage.

render7/8 and v9 were recovered from session transcripts after the scratchpad holding them was
wiped; v9's own output is the reference for what the cut should look like.

## Music

"Werq" by Kevin MacLeod (incompetech.com), CC BY 4.0, exactly 125 BPM. Download it to
`../out/music/Werq.mp3`. The drop's downbeat is at 93.182 s in the track; the mux starts the
track at 87.422 s so it lands on bar 3 (5.76 s) of the video.

## Takes

All 30 fps, extracted to `../out/fr/<name>/`. Film: *Charge* (Blender Studio, CC BY 4.0) on the
demo server, left part-watched at 84 s (`demo.py`'s `set_position`).

| Take | Size | How |
| --- | --- | --- |
| `flow` | 1384x890 | `take_flow.sh`: Windows build, 1400x900 window. Search "chrage", open Charge, Resume, shrink to the mini player, Home. Restarts Chudder until Charge shows the backdrop without the doubled title. |
| `episodes`, `nav`, `settings` | 1384x890 | `../take.sh` on the same window: Bonanza's episode row and season switch; open, back, open from Continue Watching (click the titles - the poster's centre plays); Settings search "subtitle" with the right pane scrolled past the downloads path. |
| `detail_desk`, `play_desk` | 1924x1090 | `../take.sh` with a 1940x1099 window: the Charge page, then 30 s of playback with the controls hidden. |
| `cast_phone` | 424x918 | `webtake.py`, touch: the Charge page, tap the cast button at 1.45 s. |
| `ipad` | 1194x834 | `webtake.py`, touch: the Charge page. |
| `play_land` | 960x540 | `webtake.py`: playing with controls up, pause at 6.8 s, resume at 11 s. Headless Chrome parks the video; start it with `video.play()`. |

## Render

    python render10.py preview 3.0 8.0 16.4 24.5   # a few frames into ../out/out10 (wipes it first)
    python render10.py                             # all 2995 frames, a few minutes
    bash mux10.sh                                  # ../out/chudder_showcase_v10.mp4

Copying the result over `assets/marketing/chudder_showcase.mp4` is a separate step; keep the
previous cut somewhere first.
