// vec3.h — minimal 3D vector math. Works on both CPU and GPU.

#ifndef VEC3_H
#define VEC3_H

#include <cmath>

struct vec3 {
    float x, y, z;

    __host__ __device__ vec3() : x(0), y(0), z(0) {}
    __host__ __device__ vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

__host__ __device__ inline vec3 operator+(const vec3& a, const vec3& b) {
    return vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}
__host__ __device__ inline vec3 operator-(const vec3& a, const vec3& b) {
    return vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}
__host__ __device__ inline vec3 operator-(const vec3& a) {
    return vec3(-a.x, -a.y, -a.z);
}
__host__ __device__ inline vec3 operator*(const vec3& a, float s) {
    return vec3(a.x * s, a.y * s, a.z * s);
}
__host__ __device__ inline vec3 operator*(float s, const vec3& a) {
    return a * s;
}
__host__ __device__ inline vec3 operator/(const vec3& a, float s) {
    return a * (1.0f / s);
}
// Component-wise multiply: used for surface_color * light_color.
__host__ __device__ inline vec3 operator*(const vec3& a, const vec3& b) {
    return vec3(a.x * b.x, a.y * b.y, a.z * b.z);
}

__host__ __device__ inline float dot(const vec3& a, const vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
__host__ __device__ inline vec3 cross(const vec3& a, const vec3& b) {
    return vec3(a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x);
}
__host__ __device__ inline float length(const vec3& a) {
    return sqrtf(dot(a, a));
}
__host__ __device__ inline vec3 normalize(const vec3& a) {
    return a / length(a);
}

#endif // VEC3_H
