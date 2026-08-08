// renderer.h — interface between the Win32 layer and the CUDA kernel.

#ifndef RENDERER_H
#define RENDERER_H

#include "camera.h"
#include "sphere.h"

// Renders one frame into d_fb, which must be DEVICE memory holding
// width * height unsigned ints. Each pixel is packed 0x00RRGGBB, which is
// exactly the layout a 32-bit Windows DIB expects.
//
// Row 0 is the TOP row of the window.
void renderFrame(unsigned int* d_fb, int width, int height,
                 const Camera& cam, const Scene& scene);

#endif // RENDERER_H
