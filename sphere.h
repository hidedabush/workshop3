// sphere.h — sphere primitive, intersection test, and the whole scene.

#ifndef SPHERE_H
#define SPHERE_H

#include "vec3.h"
#include "ray.h"

struct Sphere {
    vec3  center;
    float radius;
    vec3  color;
    bool  emissive;   // true = draw at full brightness, ignore lighting (the light bulb)

    __host__ __device__ Sphere() : radius(1.0f), emissive(false) {}
    __host__ __device__ Sphere(const vec3& c, float r, const vec3& col, bool emit = false)
        : center(c), radius(r), color(col), emissive(emit) {}
};

// Solve |origin + t*dir - center|^2 = radius^2 for the smallest t in [tMin, tMax].
// Expanding gives a*t^2 + b*t + c = 0. We use half_b to cancel the 2s and 4s.
__host__ __device__ inline bool hitSphere(const Sphere& s, const Ray& r,
                                          float tMin, float tMax, float& tHit)
{
    vec3  oc      = r.origin - s.center;
    float a       = dot(r.dir, r.dir);
    float half_b  = dot(oc, r.dir);
    float c       = dot(oc, oc) - s.radius * s.radius;

    float disc = half_b * half_b - a * c;
    if (disc < 0.0f) return false;          // no real root: the ray misses

    float sqrtD = sqrtf(disc);

    // Try the near root first, then the far one.
    float root = (-half_b - sqrtD) / a;
    if (root < tMin || root > tMax) {
        root = (-half_b + sqrtD) / a;
        if (root < tMin || root > tMax) return false;
    }

    tHit = root;
    return true;
}

// ---------------------------------------------------------------------------
// The scene is small enough to pass to the kernel by value as an argument.
// No cudaMalloc, no constant memory, no globals.
// ---------------------------------------------------------------------------
#define MAX_SPHERES 8

struct Scene {
    Sphere spheres[MAX_SPHERES];
    int    count;

    vec3   lightPos;
    vec3   lightColor;
    float  lightPower;

    __host__ __device__ Scene() : count(0), lightPower(1.0f) {}
};

#endif // SPHERE_H
