// ray.h — a ray is just an origin and a direction.

#ifndef RAY_H
#define RAY_H

#include "vec3.h"

struct Ray {
    vec3 origin;
    vec3 dir;

    __host__ __device__ Ray() {}
    __host__ __device__ Ray(const vec3& o, const vec3& d) : origin(o), dir(d) {}
};

// The point reached after travelling distance t along the ray.
__host__ __device__ inline vec3 rayAt(const Ray& r, float t) {
    return r.origin + r.dir * t;
}

#endif // RAY_H
