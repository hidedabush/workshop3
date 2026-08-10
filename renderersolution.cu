// renderersolution.cu — Complete solution for ray tracing renderer

#include <cstdio>

#include "renderer.h"
#include "vec3.h"
#include "raysolution.h"  // Use solution version
#include "sphere.h"
#include "camera.h"

// ---------------------------------------------------------------------------
// Find the nearest (closest) sphere that the ray intersects.
// Iterates through all spheres and tracks the one with the smallest t value.
//
// Parameters:
//   scene - the scene containing all spheres
//   r     - the ray to test
//   tMin  - minimum parameter value (start of valid ray segment)
//   tMax  - maximum parameter value (end of valid ray segment)
//   tBest - (output) the t value of the closest intersection
//
// Returns: sphere index (0 to count-1) if hit, or -1 if no intersection.
// ---------------------------------------------------------------------------
__device__ int closestHit(const Scene& scene, const Ray& r,
                          float tMin, float tMax, float& tBest)
{
    int   best = -1;
    float closest = tMax;  // Start with the far clipping plane

    // Test each sphere in the scene
    for (int i = 0; i < scene.count; i++) {
        float t;
        // Check if ray intersects this sphere in [tMin, closest]
        if (hitSphere(scene.spheres[i], r, tMin, closest, t)) {
            // Found a closer intersection; update our best hit
            closest = t;
            best    = i;
        }
    }

    tBest = closest;
    return best;
}

// ---------------------------------------------------------------------------
// Determine if a point is in shadow with respect to the light source.
// Casts a ray from the point toward the light; if any non-emissive sphere blocks it,
// the point is in shadow (we return true).
//
// Parameters:
//   scene      - the scene with all spheres
//   p          - the surface point to test for shadowing
//   toLight    - normalized direction vector towards the light
//   distToLight - distance from p to the light
//
// Returns: true if in shadow, false if lit.
// ---------------------------------------------------------------------------
__device__ bool inShadow(const Scene& scene, const vec3& p, const vec3& toLight,
                         float distToLight)
{
    // Create a ray starting from the surface point toward the light
    Ray shadowRay(p, toLight);

    // Test for intersection with each sphere
    for (int i = 0; i < scene.count; i++) {
        // Skip the emissive light bulb; it doesn't cast shadows
        if (scene.spheres[i].emissive) continue;

        float t;
        // Test if this sphere intersects the shadow ray between the surface and the light.
        // tMin=0.001f prevents the surface from shadowing itself due to floating-point rounding.
        if (hitSphere(scene.spheres[i], shadowRay, 0.001f, distToLight, t)) {
            return true;  // Something blocks the light; we're in shadow
        }
    }
    return false;  // Nothing blocks the light; point is lit
}

// ---------------------------------------------------------------------------
// Trace a single ray and compute its final color.
// This is the core ray tracing logic: find the closest hit, compute shading.
//
// Returns: RGB color vector (components in [0, 1], typically)
// ---------------------------------------------------------------------------
__device__ vec3 traceRay(const Scene& scene, const Ray& r)
{
    // Find the closest sphere (if any) that this ray hits
    float t;
    int   id = closestHit(scene, r, 0.001f, 1e20f, t);

    if (id < 0) {
        // Ray missed all objects; return a sky gradient (blue below, white above)
        vec3  unit = normalize(r.dir);
        float a    = 0.5f * (unit.y + 1.0f);  // Lerp parameter based on ray direction
        // Interpolate from white (bottom) to blue (top)
        return vec3(1.0f, 1.0f, 1.0f) * (1.0f - a) + vec3(0.35f, 0.55f, 1.0f) * a;
    }

    const Sphere& s = scene.spheres[id];

    // If the ray hit an emissive sphere (the light bulb), return its color at full brightness
    if (s.emissive) return s.color;

    // ---- Compute lighting for a non-emissive surface ----

    // Intersection point on the surface
    vec3 p = rayAt(r, t);
    // Outward-facing surface normal (sphere normal is simply radial from center)
    vec3 n = normalize(p - s.center);

    // Vector pointing from surface toward the light
    vec3  toLight     = scene.lightPos - p;
    float distToLight = length(toLight);
    vec3  lightDir    = toLight / distToLight;  // Normalized direction to light

    // ---- Diffuse (Lambertian) shading ----
    // Brightness is proportional to cos(angle between normal and light direction),
    // clamped to [0, 1]. If angle is > 90°, clamped to 0 (no light from behind).
    float diffuse = fmaxf(dot(n, lightDir), 0.0f);

    // ---- Shadow check ----
    // If point is in shadow, black it out (diffuse = 0)
    if (diffuse > 0.0f && inShadow(scene, p, lightDir, distToLight - 0.001f)) {
        diffuse = 0.0f;
    }

    // ---- Light attenuation ----
    // Inverse-square falloff with a softening term (1 + 0.05*d^2) to avoid
    // the light blowing out the color when very close to the source
    float atten = scene.lightPower / (1.0f + 0.05f * distToLight * distToLight);

    // ---- Combine components ----
    // Final color = surface_color * light_color * (diffuse * attenuation) + ambient
    const float ambient = 0.08f;  // Small ambient term so shadows aren't pure black
    return s.color * scene.lightColor * (diffuse * atten) + s.color * ambient;
}

// ---------------------------------------------------------------------------
// Convert a linear RGB color to a 32-bit packed Windows DIB format.
// Applies gamma correction (sqrt) and clamps values to valid ranges.
//
// Input: c - RGB color with components typically in [0, 1]
// Output: 32-bit unsigned int in format 0x00RRGGBB (Alpha=0, then R, G, B as bytes)
// ---------------------------------------------------------------------------
__device__ unsigned int packColor(vec3 c)
{
    // Apply gamma correction (sqrt is a cheap approximation of gamma 2.0).
    // Also clamp each channel to [0, 1] to handle out-of-range values.
    c.x = sqrtf(fminf(fmaxf(c.x, 0.0f), 1.0f));  // Red
    c.y = sqrtf(fminf(fmaxf(c.y, 0.0f), 1.0f));  // Green
    c.z = sqrtf(fminf(fmaxf(c.z, 0.0f), 1.0f));  // Blue

    // Convert each component from [0, 1] to [0, 255], rounding to nearest integer
    unsigned int r = (unsigned int)(c.x * 255.0f + 0.5f);
    unsigned int g = (unsigned int)(c.y * 255.0f + 0.5f);
    unsigned int b = (unsigned int)(c.z * 255.0f + 0.5f);

    // Pack into 32-bit format: 0x00RRGGBB
    // (bit shift left: R by 16, G by 8, B by 0)
    return (r << 16) | (g << 8) | b;
}

// ---------------------------------------------------------------------------
// CUDA kernel: one GPU thread per pixel.
// Each thread computes the color for its assigned pixel via ray tracing.
//
// Thread layout: 2D grid of 2D blocks (e.g., blocks of 16x16 threads).
// blockIdx and threadIdx are CUDA built-in variables.
// ---------------------------------------------------------------------------
__global__ void renderKernel(unsigned int* fb, int width, int height,
                             Camera cam, Scene scene)
{
    // Compute global thread coordinates (pixel position)
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    // The grid size is rounded up to whole blocks, so some threads may be out of bounds.
    // Bail out if this thread's pixel is outside the image.
    if (x >= width || y >= height) return;

    // Normalize pixel coordinates to [0, 1] for the camera.
    // Note: Windows uses top-down row order (y=0 at top), but the camera plane
    // uses bottom-up (y=0 at bottom), so v is flipped: v = 1.0 - (y / height).
    float u = (float)x / (float)(width  - 1);      // x in [0, 1], left to right
    float v = 1.0f - (float)y / (float)(height - 1);  // y in [0, 1], bottom to top

    // Generate the ray through this pixel
    Ray  r = cameraRay(cam, u, v);

    // Trace the ray to determine the final pixel color
    vec3 c = traceRay(scene, r);

    // Convert color to 32-bit format and write to framebuffer
    // fb is stored row-major: pixel at (x, y) is at index y*width + x
    fb[y * width + x] = packColor(c);
}

// ---------------------------------------------------------------------------
// CPU-side wrapper: configures the CUDA grid and launches the render kernel.
// This runs on the CPU; the kernel itself (renderKernel) runs on the GPU.
// ---------------------------------------------------------------------------
void renderFrame(unsigned int* d_fb, int width, int height,
                 const Camera& cam, const Scene& scene)
{
    // Configure CUDA thread and block layout:
    // - blockSize: 16x16 = 256 threads per block (good occupancy on most GPUs)
    // - gridSize: number of blocks needed to cover the entire image
    dim3 blockSize(16, 16);
    // Round up: (width + 15) / 16 blocks in x, (height + 15) / 16 blocks in y
    dim3 gridSize((width  + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    // Launch the render kernel.
    // <<<gridSize, blockSize>>> specifies the grid and block layout.
    // The Camera and Scene are passed by value; CUDA copies them to all threads.
    renderKernel<<<gridSize, blockSize>>>(d_fb, width, height, cam, scene);

    // Check if the kernel launch itself failed (rare, usually indicates a bad argument)
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        printf("Kernel launch failed: %s\n", cudaGetErrorString(err));
        return;
    }

    // CUDA kernel launches are ASYNCHRONOUS: control returns immediately,
    // but the kernel may still be running on the GPU.
    // Synchronize to wait for all threads to finish before returning to main.
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        printf("Kernel execution failed: %s\n", cudaGetErrorString(err));
    }
}
