// renderertemplate.cu — Template for students to implement ray tracing kernel
// Students will implement the core ray tracing functions

#include <cstdio>

#include "renderer.h"
#include "vec3.h"
#include "raytemplate.h"  // Use template version (students implement this)
#include "sphere.h"
#include "camera.h"

// ---------------------------------------------------------------------------
// TODO: Implement closestHit function
//
// Purpose: Find the nearest sphere that the ray intersects
//
// Input:
//   scene - the Scene containing all spheres
//   r     - the Ray to test
//   tMin  - minimum t value (start of valid ray segment)
//   tMax  - maximum t value (end of valid ray segment)
//   tBest - (output) the t value of the closest intersection
//
// Output: sphere index (0 to count-1) if hit, or -1 if no intersection
//
// Algorithm hints:
// 1. Loop through each sphere in scene.spheres (0 to scene.count)
// 2. Use hitSphere() to test ray-sphere intersection
// 3. Keep track of the closest hit (smallest t value)
// 4. Return -1 if nothing was hit
// ---------------------------------------------------------------------------
__device__ int closestHit(const Scene& scene, const Ray& r,
                          float tMin, float tMax, float& tBest)
{
    // TODO: Implement this function
    return -1;  // Placeholder: no hit
}

// ---------------------------------------------------------------------------
// TODO: Implement inShadow function
//
// Purpose: Determine if a surface point is in shadow
//
// Input:
//   scene      - the Scene with all spheres
//   p          - surface point to test
//   toLight    - normalized direction toward the light
//   distToLight - distance from p to the light
//
// Output: true if in shadow, false if lit
//
// Algorithm hints:
// 1. Create a Ray from p in the direction of toLight
// 2. Loop through spheres and test if any block the light
// 3. Skip emissive spheres (they don't cast shadows)
// 4. Use tMin=0.001f to avoid self-shadowing
// ---------------------------------------------------------------------------
__device__ bool inShadow(const Scene& scene, const vec3& p, const vec3& toLight,
                         float distToLight)
{
    // TODO: Implement this function
    return false;  // Placeholder: no shadow
}

// ---------------------------------------------------------------------------
// TODO: Implement traceRay function
//
// Purpose: Trace a single ray and compute its final color
//
// Input:
//   scene - the Scene
//   r     - the Ray to trace
//
// Output: RGB color (vec3 with components in [0, 1])
//
// Algorithm outline:
// 1. Find the closest hit using closestHit()
// 2. If no hit, return sky gradient:
//    - Normalize ray direction
//    - Lerp between white (bottom) and blue (top)
// 3. If hit an emissive sphere, return its color
// 4. Otherwise, compute lighting:
//    a. Get surface normal (for sphere: normalize(hit_point - center))
//    b. Compute direction to light
//    c. Compute diffuse lighting (dot product, clamped to [0,1])
//    d. Check if in shadow; if so, set diffuse to 0
//    e. Compute light attenuation (inverse-square with softening)
//    f. Return: surface_color * light_color * (diffuse * atten) + ambient
// ---------------------------------------------------------------------------
__device__ vec3 traceRay(const Scene& scene, const Ray& r)
{
    // TODO: Implement this function
    // Placeholder: return a debug gradient
    vec3 unit = normalize(r.dir);
    float a = 0.5f * (unit.y + 1.0f);
    return vec3(1.0f, 1.0f, 1.0f) * (1.0f - a) + vec3(0.35f, 0.55f, 1.0f) * a;
}

// ---------------------------------------------------------------------------
// HELPER: Pack RGB color into 32-bit format (already implemented for students)
// Apply gamma correction and clamp to [0, 1]
// ---------------------------------------------------------------------------
__device__ unsigned int packColor(vec3 c)
{
    c.x = sqrtf(fminf(fmaxf(c.x, 0.0f), 1.0f));
    c.y = sqrtf(fminf(fmaxf(c.y, 0.0f), 1.0f));
    c.z = sqrtf(fminf(fmaxf(c.z, 0.0f), 1.0f));

    unsigned int r = (unsigned int)(c.x * 255.0f + 0.5f);
    unsigned int g = (unsigned int)(c.y * 255.0f + 0.5f);
    unsigned int b = (unsigned int)(c.z * 255.0f + 0.5f);

    return (r << 16) | (g << 8) | b;
}

// ---------------------------------------------------------------------------
// CUDA KERNEL: One thread per pixel (already implemented for students)
// ---------------------------------------------------------------------------
__global__ void renderKernel(unsigned int* fb, int width, int height,
                             Camera cam, Scene scene)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x >= width || y >= height) return;

    float u = (float)x / (float)(width  - 1);
    float v = 1.0f - (float)y / (float)(height - 1);

    Ray  r = cameraRay(cam, u, v);
    vec3 c = traceRay(scene, r);

    fb[y * width + x] = packColor(c);
}

// ---------------------------------------------------------------------------
// CPU LAUNCHER: Configure grid and launch kernel (already implemented)
// ---------------------------------------------------------------------------
void renderFrame(unsigned int* d_fb, int width, int height,
                 const Camera& cam, const Scene& scene)
{
    dim3 blockSize(16, 16);
    dim3 gridSize((width  + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    renderKernel<<<gridSize, blockSize>>>(d_fb, width, height, cam, scene);

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        printf("Kernel launch failed: %s\n", cudaGetErrorString(err));
        return;
    }

    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        printf("Kernel execution failed: %s\n", cudaGetErrorString(err));
    }
}
