@echo off
rem Configure and build sugarscape_gpu with Ninja inside the Visual Studio developer environment.
rem Usage: scripts\build.cmd [build-dir] [SEATBELTS ON|OFF]
rem   scripts\build.cmd                    -> build\       with seatbelts ON (tests, validation)
rem   scripts\build.cmd build-fast OFF     -> build-fast\  with seatbelts OFF (benchmark)
setlocal
set "BUILD_DIR=%~1"
if "%BUILD_DIR%"=="" set "BUILD_DIR=build"
set "SEATBELTS=%~2"
if "%SEATBELTS%"=="" set "SEATBELTS=ON"

if "%VS_ROOT%"=="" set "VS_ROOT=C:\Program Files\Microsoft Visual Studio\18\Insiders"
if "%CUDA_PATH%"=="" set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"
set "CMAKE=%VS_ROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

call "%VS_ROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=%CUDA_PATH%\bin;%VS_ROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
set "FLAMEGPU_SHARE_USAGE_STATISTICS=OFF"

cd /d "%~dp0.."
"%CMAKE%" -S . -B "%BUILD_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" -DCMAKE_CUDA_ARCHITECTURES=89 ^
  -DFLAMEGPU_SEATBELTS=%SEATBELTS% -DFLAMEGPU_SHARE_USAGE_STATISTICS=OFF || exit /b 1
rem FLAME GPU's MSVC workaround also links flamegpu.lib by absolute path, which Ninja sees as a file with no
rem rule; building the library first makes that path exist.
"%CMAKE%" --build "%BUILD_DIR%" --target flamegpu --parallel 8 || exit /b 1
"%CMAKE%" --build "%BUILD_DIR%" --target sugarscape_gpu --parallel 8 || exit /b 1
