// raytemplate.h — Template for students to implement ray tracing
// TODO: Implement the Ray structure and rayAt function

#ifndef RAYTEMPLATE_H
#define RAYTEMPLATE_H

#include "vec3.h"

// TODO: Create a Ray struct that stores:
// - origin (vec3): starting point of the ray
// - dir (vec3): direction the ray travels
// Include two constructors:
// - Default constructor
// - Constructor that takes origin and direction parameters

// HINT: Use __host__ __device__ qualifiers for CUDA compatibility


// TODO: Implement rayAt function
// Input: a Ray and a parameter t (float)
// Output: the point at distance t along the ray
// Formula: p(t) = origin + t * direction
// Use __host__ __device__ inline for CUDA compatibility

// HINT: This should be a one-liner using vector math


#endif // RAYTEMPLATE_H
