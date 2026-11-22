# Video to Picture

A zero-setup Windows batch tool: **drag and drop one or many video files** onto `Video to Picture.bat` and it extracts an even grid of PNG frames from **each** video — its own folder, named after the video, created next to the video.

## What it does

1. Finds `ffmpeg` / `ffprobe` — or **installs them for you** (see Self-healing below).
2. Asks once: *"Frames to grab from EACH of the N video(s)"*.
3. For every dropped file, independently:
   - probes the duration,
   - computes an evenly spaced interval,
   - extracts exactly that many frames per video into `<video folder>\<name>\<name>_0001.png ...`.
4. Prints a per-file result and a final tally. One bad file never stops the rest.

```
Drop:   holiday.mp4  concert.mkv  broken.mp4
Enter:  10
Result: holiday\holiday_0001.png ... _0010.png
        concert\concert_0001.png ... _0010.png
        [SKIP] broken.mp4 - not a readable video
        Finished: 2 ok, 1 failed, out of 3 file(s).
```

## Self-healing dependency chain

The script never tells you to "please install ffmpeg". It tries, in order:

| # | Source | Notes |
|---|--------|-------|
| 1 | `tools\` folder next to the .bat | Bundled copies always win. You can drop `ffmpeg.exe` + `ffprobe.exe` there on a machine with no internet. |
| 2 | System `PATH` | Validated by actually running `-version`, so broken Store stubs are rejected. |
| 3 | `winget install Gyan.FFmpeg` | User scope, no admin, agreements auto-accepted; package located even before PATH refreshes. |
| 4 | Portable download | Grabs the official [FFmpeg-Builds](https://github.com/FFmpeg-Builds/FFmpeg-Builds) win64 GPL zip (~180 MB) via PowerShell and unpacks only the two .exe files into `tools\`. One-time, then offline forever. |

If everything fails, you get a clear message with both manual options.

### Environment switches

| Variable | Effect |
|----------|--------|
| `V2P_NO_INSTALL=1` | Never auto-install — fail fast if ffmpeg is missing (useful on locked-down machines). |
| `V2P_NO_WINGET=1` | Skip winget, go straight to the portable download. |

## Why this batch file is sturdier than it looks

Every one of these was a real failure mode that got tested out:

- **cmd's quote-stripping rule** mangles `for /f ('"C:\path with space\ffprobe.exe" ...')` — ffprobe output is routed through a temp file instead.
- **`[0-9]` character classes** match nothing in `dir` on recent Windows builds — patterns use `?`/`*` only.
- **`for %%P in ("????")` silently glob-expands against the current directory** (`?` is a FOR wildcard!) so pattern-loops iterate zero times — statements are unrolled.
- **Trailing `?` matches an empty stem** in Win32 wildcards, so length-pattern counting triple-counts — counting uses the file prefix instead.
- **GNU tool shadowing**: launched from shells with a polluted `PATH`, bare `find`/`findstr`/`where` can resolve to coreutils busybox binaries — all helpers are pinned to `%SystemRoot%\System32`.
- **`-vsync` was removed in ffmpeg 9** — the script tries `-fps_mode vfr` first and retries with `-vsync vfr` for old builds.
- Duration parsing falls back to the legacy console `Duration: HH:MM:SS` line for containers (e.g. MPEG-TS) where `format=duration` returns `N/A`.
- Leading-zero octal traps (`08`, `09`) avoided in the time math; interval clamped so absurd durations/counts can't divide by zero or overflow.
- Re-running never nukes your folder: it only deletes its own numbered frames, and if a *file* blocks the output folder name, it falls back to `<name>_frames`.

## Known limits

- File names containing `!` are not supported (batch delayed expansion).
- Windows caps the dropped-argument list at ~8,100 characters of total path length — for 200+ files at once, drop them in batches.
- Videos shorter than 1 second are skipped (nothing sensible to grab).
- The output folder is dedicated to the script's frames; other files matching `<name>_*.png` in it may be cleaned on re-runs.

## Requirements

- Windows 7+ (x64), PowerShell (present by default) for the last-resort installer only.
- No admin rights, no Python, no manual ffmpeg setup.

## License

All rights reserved.
