// renderer.h — interface between the Win32 layer and the CUDA kernel.

#ifndef RENDERER_H
#define RENDERER_H

#include "camera.h"
#include "sphere.h"

// Render a frame by launching CUDA kernels to trace rays and produce pixels.
//
// Parameters:
//   d_fb      - GPU (device) memory: array of width*height unsigned ints, each a pixel.
//               Pixel format: 0x00RRGGBB (Alpha=0, Red, Green, Blue as 8-bit components).
//               This format matches Windows DIB (Device Independent Bitmap) expectations.
//   width     - Image width in pixels
//   height    - Image height in pixels
//   cam       - Camera specifying view origin and image plane
//   scene     - Scene containing spheres and lighting
//
// Memory layout: pixels are stored row-major, with row 0 being the TOP of the window
// (this is the standard Windows top-down bitmap order).
void renderFrame(unsigned int* d_fb, int width, int height,
                 const Camera& cam, const Scene& scene);

#endif // RENDERER_H
