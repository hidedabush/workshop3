@echo off
REM Initialize MSVC compiler environment for CUDA

set VS_PATH=
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Professional"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
)

if not defined VS_PATH (
    echo Error: Visual Studio not found. Please install Visual Studio with C++ workload.
    exit /b 1
)

call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64

if %errorlevel% neq 0 (
    echo Error: Failed to initialize MSVC environment
    exit /b %errorlevel%
)

nvcc -O2 -gencode arch=compute_89,code=sm_89 main.cu renderer.cu -o raytracer.exe -luser32 -lgdi32
if %errorlevel% neq 0 (
    echo.
    echo BUILD FAILED
    exit /b %errorlevel%
)

echo Build succeeded. Launching...
echo.
.\raytracer.exe
