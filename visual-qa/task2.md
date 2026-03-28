# Visual QA — Task 2: Timeline + BPM Grid + Note Rendering

**Mode:** Static screenshots (1fps), 16 frames
**Date:** 2026-03-28

## Verdict: PASS

## Checks

### Task Goal (from Verify description)
- [x] Sample chart (52 notes) loaded and displayed
- [x] Blue normal notes visible in NORMAL row
- [x] Green top notes visible in TOP 0/1/2 rows
- [x] Purple vertical notes visible in V0-V6 rows
- [x] Long notes (long_normal, long_top, long_vertical) render as horizontal pills with rounded caps
- [x] Chain notes render with connector lines between members (visible in frame00000004)
- [x] BPM grid lines (beat subdivisions, measure lines) visible throughout
- [x] Ruler shows measure numbers at top
- [x] BPM:120 marker visible at t=0, BPM:150 marker visible at t=20 (measure 11 line)
- [x] Zoom in/out works (frame00000006=500pps, frame00000008=80pps)
- [x] Track row labels (TOP 0-2, NORMAL, V 0-6) correctly align with timeline rows

### Visual Consistency
- Track backgrounds: brown (TOP rows), dark blue (NORMAL), darker blue (V rows) — matches spec colors
- Grid lines: bright white measure lines, medium beat lines, faint sub-division lines — all visible
- Note colors: blue=#4D66FF (normal), green=#1AE64D (top), purple=#8855FF (vertical) — correct
- Row alignment: 36px header spacer added to TrackHeaderList to align with timeline ruler+BPM band

### Issues Found & Fixed
1. **Row alignment offset**: TrackHeaderList had no header to match Timeline's 36px ruler+BPM band.
   Fix: Added `HeaderSpacer` Control (36px) at top of TrackHeaderList in ChartEditor.tscn.
2. **NoteRenderer.get_row_y** was missing the 36px HEADER_HEIGHT offset.
   Fix: Added `HEADER_HEIGHT = RULER_HEIGHT + BPM_BAND_HEIGHT = 36` constant to NoteRenderer.gd.

### Key Screenshots
- `frame00000002.png` — default view (t=0-5s, 200pps): normal, top, vertical notes aligned
- `frame00000004.png` — scroll t=16-18s: chain notes with connectors in NORMAL row
- `frame00000008.png` — zoom 500pps: long notes (pills) clearly visible, all note types correct
- `frame00000010.png` — BPM change at t=20: BPM:150 marker shown with vertical line
- `frame00000014.png` — 100pps overview: all note types visible across full timeline
