// sphere.h — sphere primitive, intersection test, and the whole scene.

#ifndef SPHERE_H
#define SPHERE_H

#include "vec3.h"
#include "ray.h"

// Sphere geometry: center point, radius, surface color, and emission flag.
struct Sphere {
    vec3  center;         // Center point of the sphere in world space
    float radius;         // Radius of the sphere
    vec3  color;          // RGB color of the sphere's surface
    bool  emissive;       // true = draw at full brightness; false = apply shading/lighting
                          // (Emissive spheres represent light sources like the light bulb)

    // Default constructor: unit sphere at origin, non-emissive
    __host__ __device__ Sphere() : radius(1.0f), emissive(false) {}
    // Constructor: create sphere with center, radius, color, and optional emissive flag
    __host__ __device__ Sphere(const vec3& c, float r, const vec3& col, bool emit = false)
        : center(c), radius(r), color(col), emissive(emit) {}
};

// Ray-sphere intersection test: find where the ray hits the sphere (if at all).
//
// Solves: |ray.origin + t*ray.dir - sphere.center|^2 = sphere.radius^2
// This is a quadratic equation in t: a*t^2 + b*t + c = 0
// We use "half_b" optimization to simplify (cancels 2s and 4s in the quadratic formula).
//
// Returns true if the ray intersects the sphere in the range [tMin, tMax].
// On success, tHit is set to the t value of the closest intersection.
__host__ __device__ inline bool hitSphere(const Sphere& s, const Ray& r,
                                          float tMin, float tMax, float& tHit)
{
    // Vector from sphere center to ray origin
    vec3  oc      = r.origin - s.center;

    // Quadratic coefficients for a*t^2 + b*t + c = 0
    float a       = dot(r.dir, r.dir);         // (should be ~1 if dir is normalized)
    float half_b  = dot(oc, r.dir);            // This is really b/2
    float c       = dot(oc, oc) - s.radius * s.radius;

    // Compute discriminant: b^2 - 4ac (scaled down by 4, hence half_b^2 - a*c)
    float disc = half_b * half_b - a * c;
    if (disc < 0.0f) return false;             // Negative discriminant: no intersection

    float sqrtD = sqrtf(disc);

    // Quadratic formula gives two solutions: t = (-b ± sqrt(discriminant)) / 2a
    // Try the near intersection first (smallest t), then the far one (largest t)
    float root = (-half_b - sqrtD) / a;        // Closer intersection
    if (root < tMin || root > tMax) {
        root = (-half_b + sqrtD) / a;          // Farther intersection
        if (root < tMin || root > tMax) return false;  // Both outside valid range
    }

    tHit = root;
    return true;
}

// ---------------------------------------------------------------------------
// Scene structure: holds all geometry and lighting information.
// Small enough to pass directly to the CUDA kernel (no GPU memory allocation needed).
// No cudaMalloc, no constant memory, no global arrays — just pass by value.
// ---------------------------------------------------------------------------
#define MAX_SPHERES 8   // Maximum number of spheres in the scene

struct Scene {
    Sphere spheres[MAX_SPHERES];  // Array of sphere primitives
    int    count;                 // Number of spheres actually used (0 to MAX_SPHERES)

    vec3   lightPos;              // Position of the point light source
    vec3   lightColor;            // RGB color of the light (typically white/warm)
    float  lightPower;            // Intensity multiplier for the light

    // Default constructor: empty scene with no spheres
    __host__ __device__ Scene() : count(0), lightPower(1.0f) {}
};

#endif // SPHERE_H
