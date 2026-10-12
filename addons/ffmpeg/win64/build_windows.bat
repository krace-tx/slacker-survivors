@echo off
setlocal

echo [EIRTeam.FFmpeg] Starting Windows win64 GDExtension build...

where scons >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] SCons not found in PATH. Please install Python and SCons: pip install scons
    exit /b 1
)

set BUILD_DIR=%TEMP%\ffmpeg-windows-build
if exist "%BUILD_DIR%" (
    echo [INFO] Cleaning prior build directory %BUILD_DIR%...
    rmdir /s /q "%BUILD_DIR%"
)

echo [INFO] Cloning EIRTeam.FFmpeg...
git clone --depth 1 --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git "%BUILD_DIR%"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Git clone failed.
    exit /b 1
)

cd /d "%BUILD_DIR%\gdextension_build"

echo [INFO] Building Release template...
scons platform=windows target=template_release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] SCons build template_release failed.
    exit /b 1
)

echo [INFO] Building Debug template...
scons platform=windows target=template_debug
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] SCons build template_debug failed.
    exit /b 1
)

echo [INFO] Copying binaries to %~dp0...
copy /y "%BUILD_DIR%\gdextension_build\build\addons\ffmpeg\win64\*" "%~dp0"

echo [SUCCESS] Windows win64 FFmpeg binaries updated successfully!
endlocal
