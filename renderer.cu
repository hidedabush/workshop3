// renderer.cu — the actual ray tracer. One CUDA thread per pixel.

#include <cstdio>

#include "renderer.h"
#include "vec3.h"
#include "ray.h"
#include "sphere.h"
#include "camera.h"

// ---------------------------------------------------------------------------
// Find the nearest sphere hit by this ray.
// Returns the index of the sphere, or -1 if the ray hits nothing.
// ---------------------------------------------------------------------------
__device__ int closestHit(const Scene& scene, const Ray& r,
                          float tMin, float tMax, float& tBest)
{
    int   best = -1;
    float closest = tMax;

    for (int i = 0; i < scene.count; i++) {
        float t;
        if (hitSphere(scene.spheres[i], r, tMin, closest, t)) {
            closest = t;
            best    = i;
        }
    }

    tBest = closest;
    return best;
}

// ---------------------------------------------------------------------------
// Is the point p in shadow with respect to the light?
// Shoot a ray towards the light; if anything solid blocks it, we're shadowed.
// ---------------------------------------------------------------------------
__device__ bool inShadow(const Scene& scene, const vec3& p, const vec3& toLight,
                         float distToLight)
{
    Ray shadowRay(p, toLight);

    for (int i = 0; i < scene.count; i++) {
        if (scene.spheres[i].emissive) continue;   // the bulb doesn't cast shadow
        float t;
        // 0.001f avoids the surface shadowing itself due to float rounding.
        if (hitSphere(scene.spheres[i], shadowRay, 0.001f, distToLight, t)) {
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Trace one ray and return its colour.
// ---------------------------------------------------------------------------
__device__ vec3 traceRay(const Scene& scene, const Ray& r)
{
    float t;
    int   id = closestHit(scene, r, 0.001f, 1e20f, t);

    if (id < 0) {
        // Miss: blue-to-white vertical sky gradient.
        vec3  unit = normalize(r.dir);
        float a    = 0.5f * (unit.y + 1.0f);
        return vec3(1.0f, 1.0f, 1.0f) * (1.0f - a) + vec3(0.35f, 0.55f, 1.0f) * a;
    }

    const Sphere& s = scene.spheres[id];

    // The light bulb is drawn at full brightness so you can see where it is.
    if (s.emissive) return s.color;

    vec3 p = rayAt(r, t);
    vec3 n = normalize(p - s.center);          // outward surface normal

    vec3  toLight     = scene.lightPos - p;
    float distToLight = length(toLight);
    vec3  lightDir    = toLight / distToLight;

    // Lambert: brightness = cos(angle between normal and light), clamped at 0.
    float diffuse = fmaxf(dot(n, lightDir), 0.0f);

    if (diffuse > 0.0f && inShadow(scene, p, lightDir, distToLight - 0.001f)) {
        diffuse = 0.0f;
    }

    // Inverse-square falloff, softened so it doesn't blow out up close.
    float atten = scene.lightPower / (1.0f + 0.05f * distToLight * distToLight);

    const float ambient = 0.08f;               // so shadows aren't pure black
    return s.color * scene.lightColor * (diffuse * atten) + s.color * ambient;
}

// ---------------------------------------------------------------------------
// Pack a linear colour into 0x00RRGGBB, applying a cheap gamma curve.
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
// One thread = one pixel.
// ---------------------------------------------------------------------------
__global__ void renderKernel(unsigned int* fb, int width, int height,
                             Camera cam, Scene scene)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    // The grid is rounded up to whole blocks, so edge threads must bail out.
    if (x >= width || y >= height) return;

    // Screen coords in [0,1]. Windows rows go top-down, the camera plane goes
    // bottom-up, so v is flipped.
    float u = (float)x / (float)(width  - 1);
    float v = 1.0f - (float)y / (float)(height - 1);

    Ray  r = cameraRay(cam, u, v);
    vec3 c = traceRay(scene, r);

    fb[y * width + x] = packColor(c);
}

// ---------------------------------------------------------------------------
// Host-side launcher.
// ---------------------------------------------------------------------------
void renderFrame(unsigned int* d_fb, int width, int height,
                 const Camera& cam, const Scene& scene)
{
    dim3 blockSize(16, 16);
    dim3 gridSize((width  + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    // Camera and Scene are small, so they travel as plain kernel arguments.
    renderKernel<<<gridSize, blockSize>>>(d_fb, width, height, cam, scene);

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        printf("Kernel launch failed: %s\n", cudaGetErrorString(err));
        return;
    }

    // Kernel launches are asynchronous. Wait before copying the pixels back.
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        printf("Kernel execution failed: %s\n", cudaGetErrorString(err));
    }
}
