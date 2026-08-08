// camera.h — a fixed pinhole camera, rebuilt on the CPU every frame.

#ifndef CAMERA_H
#define CAMERA_H

#include "vec3.h"
#include "ray.h"

struct Camera {
    vec3 origin;      // eye position
    vec3 lowerLeft;   // world-space corner of the virtual image plane
    vec3 horizontal;  // full width vector of the image plane
    vec3 vertical;    // full height vector of the image plane
};

// Build a camera that looks from `eye` towards `target`.
// fovDegrees is the VERTICAL field of view.
__host__ inline Camera makeCamera(const vec3& eye, const vec3& target,
                                  float fovDegrees, float aspect)
{
    const vec3 worldUp(0.0f, 1.0f, 0.0f);

    float theta      = fovDegrees * 3.14159265f / 180.0f;
    float halfHeight = tanf(theta * 0.5f);
    float halfWidth  = aspect * halfHeight;

    // Orthonormal camera basis. w points BACKWARDS (away from the target).
    vec3 w = normalize(eye - target);
    vec3 u = normalize(cross(worldUp, w));
    vec3 v = cross(w, u);

    Camera cam;
    cam.origin     = eye;
    cam.lowerLeft  = eye - u * halfWidth - v * halfHeight - w;
    cam.horizontal = u * (2.0f * halfWidth);
    cam.vertical   = v * (2.0f * halfHeight);
    return cam;
}

// Orbit the camera around `target` on a sphere of radius `distance`.
// yaw spins horizontally, pitch tilts up and down.
__host__ inline Camera makeOrbitCamera(const vec3& target, float yaw, float pitch,
                                       float distance, float fovDegrees, float aspect)
{
    vec3 offset(distance * cosf(pitch) * sinf(yaw),
                distance * sinf(pitch),
                distance * cosf(pitch) * cosf(yaw));
    return makeCamera(target + offset, target, fovDegrees, aspect);
}

// s and t are in [0,1] across the image. Returns the ray through that point.
__host__ __device__ inline Ray cameraRay(const Camera& cam, float s, float t) {
    vec3 point = cam.lowerLeft + cam.horizontal * s + cam.vertical * t;
    return Ray(cam.origin, point - cam.origin);
}

#endif // CAMERA_H
