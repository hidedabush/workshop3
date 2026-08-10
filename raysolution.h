// raysolution.h — Complete solution for ray implementation

#ifndef RAYSOLUTION_H
#define RAYSOLUTION_H

#include "vec3.h"

// Ray structure: represents a line in 3D space defined by origin point and direction.
// Parametric form: ray(t) = origin + t * dir
// (t >= 0 for points along the ray in the forward direction)
struct Ray {
    vec3 origin;  // Starting point of the ray (typically the camera)
    vec3 dir;     // Direction the ray travels (should be normalized for consistency)

    // Default constructor
    __host__ __device__ Ray() {}
    // Constructor: create ray from origin point and direction vector
    __host__ __device__ Ray(const vec3& o, const vec3& d) : origin(o), dir(d) {}
};

// Evaluate the ray at parameter t: returns the point at distance t along the ray.
// rayAt(r, 0) returns the origin.
// rayAt(r, 1) returns origin + direction.
// This is the parametric equation p(t) = origin + t * direction.
__host__ __device__ inline vec3 rayAt(const Ray& r, float t) {
    return r.origin + r.dir * t;
}

#endif // RAYSOLUTION_H
