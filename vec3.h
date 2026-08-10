// vec3.h — minimal 3D vector math. Works on both CPU and GPU.

#ifndef VEC3_H
#define VEC3_H

#include <cmath>

// 3D vector structure with x, y, z components.
// __host__ __device__ allows these functions to run on both CPU and GPU.
struct vec3 {
    float x, y, z;

    // Default constructor: initializes to (0, 0, 0)
    __host__ __device__ vec3() : x(0), y(0), z(0) {}
    // Component constructor: initializes to (x_, y_, z_)
    __host__ __device__ vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

// Vector addition: component-wise sum
__host__ __device__ inline vec3 operator+(const vec3& a, const vec3& b) {
    return vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}
// Vector subtraction: component-wise difference
__host__ __device__ inline vec3 operator-(const vec3& a, const vec3& b) {
    return vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}
// Negation: flips all components
__host__ __device__ inline vec3 operator-(const vec3& a) {
    return vec3(-a.x, -a.y, -a.z);
}
// Scalar multiplication: scales each component
__host__ __device__ inline vec3 operator*(const vec3& a, float s) {
    return vec3(a.x * s, a.y * s, a.z * s);
}
// Scalar multiplication (reversed): same as above for convenience
__host__ __device__ inline vec3 operator*(float s, const vec3& a) {
    return a * s;
}
// Scalar division: scales down by dividing by s
__host__ __device__ inline vec3 operator/(const vec3& a, float s) {
    return a * (1.0f / s);
}
// Component-wise multiply: multiplies each component separately.
// Used for combining colors (e.g., surface_color * light_color).
__host__ __device__ inline vec3 operator*(const vec3& a, const vec3& b) {
    return vec3(a.x * b.x, a.y * b.y, a.z * b.z);
}

// Dot product: a·b = ax*bx + ay*by + az*bz
// Returns scalar measuring how aligned the vectors are (range typically -1 to 1 when normalized)
__host__ __device__ inline float dot(const vec3& a, const vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
// Cross product: a × b
// Returns a vector perpendicular to both a and b
__host__ __device__ inline vec3 cross(const vec3& a, const vec3& b) {
    return vec3(a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x);
}
// Euclidean length: |a| = sqrt(a·a)
// Returns the magnitude of the vector
__host__ __device__ inline float length(const vec3& a) {
    return sqrtf(dot(a, a));
}
// Normalize: returns unit vector in the direction of a
// Used for surface normals and direction vectors in ray tracing
__host__ __device__ inline vec3 normalize(const vec3& a) {
    return a / length(a);
}

#endif // VEC3_H
