# Real-Time CUDA Ray Tracer (Windows, no libraries)

An interactive GPU ray tracer in a real window. Orbit the camera, drag the
light around, watch the shading and shadows update live.

**No CMake. No OpenGL. No GLFW/SDL/SFML. No package manager. No downloads.**

The window comes from the Win32 API (`user32.dll` / `gdi32.dll`), which is part
of Windows itself. The headers and import libraries come with the same Visual
Studio C++ workload that NVCC already requires, so there is nothing extra to
install.

## Build

Open **x64 Native Tools Command Prompt for VS**, `cd` into this folder:

```
build.bat
```

Or the single command directly:

```
nvcc -O2 main.cu renderer.cu -o raytracer.exe -luser32 -lgdi32
```

If `-l` gives you trouble on an older toolkit, this is equivalent:

```
nvcc -O2 main.cu renderer.cu -o raytracer.exe user32.lib gdi32.lib
```

## Controls

| Input | Action |
| --- | --- |
| Drag left mouse | Orbit camera |
| Arrow keys | Orbit camera |
| Mouse wheel, `W` / `S` | Zoom in / out |
| `I` `J` `K` `L` | Move light horizontally |
| `U` / `O` | Move light up / down |
| `+` / `-` | Light brightness |
| `R` | Reset view and light |
| `Esc` | Quit |

FPS is shown in the title bar. The window is resizable; buffers reallocate
automatically.

## Scene

- Large red sphere (main object) at the origin
- Small blue sphere beside it
- Huge ground sphere acting as a floor
- Small glowing sphere that *is* the light — move it and the shading follows

Shading is Lambert diffuse with distance falloff, plus one shadow ray so the
objects cast shadows on the floor and each other.

## How it works

```
CUDA kernel  ->  device buffer (uint per pixel, 0x00RRGGBB)
             ->  cudaMemcpy to host
             ->  StretchDIBits blits it to the window
```

One CUDA thread renders one pixel. At 960x540 that is 518,400 threads per
frame, which a modern GPU finishes in well under a millisecond — the
`cudaMemcpy` and the GDI blit are the slow parts, and they are still fast
enough for smooth interaction.

There is no CUDA/OpenGL interop because there is no OpenGL. That costs one
device-to-host copy per frame and buys you a build with zero dependencies.

## Files

| File | Purpose |
| --- | --- |
| `main.cu` | Win32 window, input, render loop, blit |
| `renderer.cu` | The CUDA kernel: rays, intersection, shading |
| `renderer.h` | Kernel launcher interface |
| `vec3.h` | Vector math (host + device) |
| `ray.h` | Ray struct |
| `sphere.h` | Sphere, intersection test, `Scene` |
| `camera.h` | Pinhole and orbit camera |

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `nvcc` not recognized | CUDA Toolkit not on PATH — reopen the VS command prompt |
| `Cannot find compiler 'cl.exe'` | Use the x64 Native Tools Command Prompt |
| `unresolved external symbol __imp_CreateWindowExA` | Missing `-luser32 -lgdi32` |
| Window is black | Press `R` to reset the camera and light |
| Low FPS | Shrink the window, or lower the resolution constants in `main.cu` |
| Want no console window | Add `-Xlinker /SUBSYSTEM:WINDOWS` and rename `main` to `WinMain` |

## Turning this into a workshop

The single-file-per-concept layout still works as a teaching progression:
start with a black window, add the sky gradient, add ray generation, add the
sphere test, add normals-as-colour, add Lambert, then add the movable light.
The window and input code in `main.cu` never has to change.
