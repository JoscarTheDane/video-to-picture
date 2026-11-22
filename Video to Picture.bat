@echo off
REM ============================================================
REM  Video to Picture  (v2)
REM  Drag and drop ONE or MANY video files onto this .bat
REM  -> asks how many frames to grab from EACH video
REM  -> extracts evenly spaced PNG frames from every video
REM     into its own folder named after the video,
REM     created next to that video
REM
REM  Self-healing: finds ffmpeg/ffprobe
REM     1. bundled in a "tools" folder next to this script
REM     2. on PATH
REM     3. via winget  (package install, no admin needed)
REM     4. downloads a portable build into "tools" (last resort)
REM
REM  Optional environment switches:
REM    set V2P_NO_INSTALL=1   never auto-install (fail if missing)
REM    set V2P_NO_WINGET=1    skip winget, go straight to download
REM
REM  Known limits: file names containing "!" are not supported;
REM  Windows caps the dropped-argument list at ~8100 characters.
REM ============================================================
setlocal EnableExtensions DisableDelayedExpansion
title Video to Picture

set "TOOLDIR=%~dp0tools"
set "TMPPROBE=%TEMP%\v2p_probe_%RANDOM%.tmp"

REM ============ locate ffmpeg / ffprobe ============
set "FFMPEG="
set "FFPROBE="
call :find_tools
if not defined FFMPEG (
    echo.
    echo [FATAL] ffmpeg / ffprobe not found and could not be installed.
    echo         Option 1: put ffmpeg.exe + ffprobe.exe into:
    echo             %TOOLDIR%
    echo         Option 2: install FFmpeg and make sure it is on PATH.
    echo             https://www.gyan.dev/ffmpeg/builds/
    echo.
    pause
    exit /b 1
)

REM ============ inputs ============
if "%~1"=="" (
    echo Drag and drop one or more video files onto this batch file.
    echo.
    pause
    exit /b
)

set /a NFILES=0
for %%A in (%*) do set /a NFILES+=1

REM ============ frames per video (asked once, used for every video) ============
set "totalFrames="
set /p "totalFrames=Frames to grab from EACH of the %NFILES% video(s): "
if "%totalFrames%"=="" (
    echo No value entered.
    pause
    exit /b 1
)
for /f "delims=0123456789" %%x in ("%totalFrames%") do (
    echo Invalid input "%totalFrames%" - enter a whole number.
    pause
    exit /b 1
)
if %totalFrames% LSS 1 (
    echo Enter a number of 1 or more.
    pause
    exit /b 1
)
if %totalFrames% GTR 100000 (
    echo That is too many. Enter 100000 or less.
    pause
    exit /b 1
)

REM ============ process each dropped file, one at a time ============
set /a CUR=0, OKCNT=0, FAILCNT=0
:nextfile
if "%~1"=="" goto summary
set /a CUR+=1
call :process_one %1
if errorlevel 1 ( set /a FAILCNT+=1 ) else ( set /a OKCNT+=1 )
shift
goto nextfile

:summary
if defined TMPPROBE del /q "%TMPPROBE%" >nul 2>&1
echo.
echo ============================================================
echo Finished: %OKCNT% ok, %FAILCNT% failed, out of %NFILES% file(s).
echo ============================================================
echo.
pause
exit /b 0

REM ============================================================
:process_one
setlocal EnableExtensions EnableDelayedExpansion
set "INPUT=%~1"
set "videoName=%~n1"
set "outDir=%~dp1%videoName%"
echo.
echo ------------------------------------------------------------
echo [!CUR!/!NFILES!] "!INPUT!"

if not exist "!INPUT!" (
    echo [SKIP] File not found.
    exit /b 1
)

REM ---- duration in whole seconds: machine-readable probe first ----
REM (ffprobe output goes to a temp file - calling it inside for /f with
REM  quoted paths triggers cmd's first/last-quote-stripping rule)
set "SEC="
set "dur="
"!FFPROBE!" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "!INPUT!" > "!TMPPROBE!" 2>nul
if exist "!TMPPROBE!" set /p dur=<"!TMPPROBE!"
if defined dur for /f "tokens=1 delims=." %%A in ("!dur!") do set "SEC=%%A"

REM ---- fallback: parse console "Duration: HH:MM:SS.xx" ----
if not defined SEC (
    "!FFPROBE!" -i "!INPUT!" > "!TMPPROBE!" 2>&1
    set "dline="
    if exist "!TMPPROBE!" for /f "delims=" %%L in ('%SystemRoot%\System32\findstr.exe /i /c:"Duration:" "!TMPPROBE!" 2^>nul') do set "dline=%%L"
    if defined dline (
        set "t=!dline:*Duration: =!"
        for /f "tokens=1 delims=," %%A in ("!t!") do set "t=%%A"
        for /f "tokens=1,2,3 delims=:." %%a in ("!t!") do set /a "H=1%%a-100, M=1%%b-100, S=1%%c-100"
        set /a "SEC=H*3600+M*60+S"
    )
)

REM ---- SEC must be a clean number now ----
if defined SEC for /f "delims=0123456789" %%x in ("!SEC!") do set "SEC="
if not defined SEC (
    echo [SKIP] Could not read a duration - not a readable video file?
    exit /b 1
)
if !SEC! LEQ 0 (
    echo [SKIP] Zero-length video - nothing to grab.
    exit /b 1
)

REM ---- output folder: reuse it, never delete anything that is not ours ----
if exist "!outDir!" if not exist "!outDir!\" set "outDir=!outDir!_frames"
if not exist "!outDir!\" mkdir "!outDir!" 2>nul
if not exist "!outDir!\" (
    echo [SKIP] Cannot create output folder "!outDir!".
    exit /b 1
)
REM clean only our own numbered frames from any previous run
REM (note: cmd's [0-9] classes are unreliable in dir, and bare ? patterns
REM  cannot be looped via "for in" because FOR globs them against the CWD)
del /q "!outDir!\!videoName!_????.png" >nul 2>&1
del /q "!outDir!\!videoName!_?????.png" >nul 2>&1
del /q "!outDir!\!videoName!_??????.png" >nul 2>&1

REM ---- interval (clamped so absurdly long files cannot overflow the math) ----
if !SEC! GTR 2000000 set "SEC=2000000"
set /a interval=(!SEC! * 1000) / !totalFrames!
if !interval! LSS 1 set "interval=1"

echo Duration: !SEC! s - grabbing !totalFrames! frames, one every !interval! ms.

REM -vsync was removed in ffmpeg 9.0; -fps_mode is its replacement.
REM Try the modern flag first, retry with the legacy one for old builds.
"!FFMPEG!" -hide_banner -loglevel error -stats -y -i "!INPUT!" -vf "fps=1000/!interval!" -fps_mode vfr "!outDir!\!videoName!_%%04d.png"
if errorlevel 1 (
    "!FFMPEG!" -hide_banner -loglevel error -stats -y -i "!INPUT!" -vf "fps=1000/!interval!" -vsync vfr "!outDir!\!videoName!_%%04d.png"
)

set "cnt=0"
for /f "delims=" %%F in ('dir /b /a-d "!outDir!\!videoName!_*.png" 2^>nul') do set /a cnt+=1
if !cnt! EQU 0 (
    echo [FAIL] No frames were extracted.
    exit /b 1
)
echo [OK] !cnt! frames saved to: "!outDir!"
exit /b 0

REM ============================================================
:find_tools
REM ---- 1) copies bundled next to this script ----
if exist "%TOOLDIR%\ffmpeg.exe" if exist "%TOOLDIR%\ffprobe.exe" (
    set "FFMPEG=%TOOLDIR%\ffmpeg.exe"
    set "FFPROBE=%TOOLDIR%\ffprobe.exe"
    exit /b 0
)

REM ---- 2) PATH ----
for /f "delims=" %%P in ('%SystemRoot%\System32\where.exe ffmpeg 2^>nul') do if not defined FFMPEG set "FFMPEG=%%P"
for /f "delims=" %%P in ('%SystemRoot%\System32\where.exe ffprobe 2^>nul') do if not defined FFPROBE set "FFPROBE=%%P"
if defined FFMPEG if defined FFPROBE (
    REM reject broken stubs (e.g. WindowsApps aliases that are not real binaries)
    "%FFMPEG%" -version >nul 2>&1
    if errorlevel 1 set "FFMPEG="
    "%FFPROBE%" -version >nul 2>&1
    if errorlevel 1 set "FFPROBE="
    if defined FFMPEG if defined FFPROBE exit /b 0
)
set "FFMPEG="
set "FFPROBE="

if defined V2P_NO_INSTALL (
    echo FFmpeg not found - auto-install is disabled ^(V2P_NO_INSTALL^).
    exit /b 1
)

REM ---- 3) winget package install (user scope, no admin) ----
if not defined V2P_NO_WINGET (
    %SystemRoot%\System32\where.exe winget >nul 2>&1
    if not errorlevel 1 (
        echo FFmpeg not found - installing it with winget...
        winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements >nul 2>&1
        REM PATH is not refreshed in this window, so locate the package directly
        for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*") do (
            for /d %%E in ("%%D\ffmpeg-*") do (
                if exist "%%E\bin\ffmpeg.exe" if exist "%%E\bin\ffprobe.exe" (
                    set "FFMPEG=%%E\bin\ffmpeg.exe"
                    set "FFPROBE=%%E\bin\ffprobe.exe"
                )
            )
        )
        if defined FFMPEG if defined FFPROBE (
            echo Using FFmpeg installed via winget.
            exit /b 0
        )
        set "FFMPEG="
        set "FFPROBE="
    )
)

REM ---- 4) portable download (last resort, no admin needed) ----
echo FFmpeg still not found - downloading a portable build into:
echo     %TOOLDIR%
echo This is a one-time download of roughly 180 MB. Please wait...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; $tmp=Join-Path $env:TEMP 'v2p_ffmpeg'; $zip=Join-Path $tmp 'ffmpeg.zip'; New-Item -ItemType Directory -Force -Path $tmp | Out-Null; Invoke-WebRequest -Uri 'https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip' -OutFile $zip; Expand-Archive -Path $zip -DestinationPath $tmp -Force; $bin=Join-Path $tmp 'ffmpeg-master-latest-win64-gpl\bin'; New-Item -ItemType Directory -Force -Path '%TOOLDIR%' | Out-Null; Copy-Item (Join-Path $bin 'ffmpeg.exe') '%TOOLDIR%\ffmpeg.exe' -Force; Copy-Item (Join-Path $bin 'ffprobe.exe') '%TOOLDIR%\ffprobe.exe' -Force; Remove-Item $tmp -Recurse -Force"
if exist "%TOOLDIR%\ffmpeg.exe" if exist "%TOOLDIR%\ffprobe.exe" (
    set "FFMPEG=%TOOLDIR%\ffmpeg.exe"
    set "FFPROBE=%TOOLDIR%\ffprobe.exe"
    echo FFmpeg is now installed in "%TOOLDIR%".
    exit /b 0
)
echo Auto-install failed.
exit /b 1
