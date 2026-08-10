// camera.h — a fixed pinhole camera, rebuilt on the CPU every frame.

#ifndef CAMERA_H
#define CAMERA_H

#include "vec3.h"
#include "ray.h"

// Pinhole camera model: stores the origin and basis vectors of the image plane.
// The image plane is a rectangle in 3D space; rays are shot through each pixel.
struct Camera {
    vec3 origin;      // Eye position (where rays originate from)
    vec3 lowerLeft;   // World-space position of the bottom-left corner of the image plane
    vec3 horizontal;  // Vector from lowerLeft to lowerRight (spans the full width)
    vec3 vertical;    // Vector from lowerLeft to upperLeft (spans the full height)
};

// Construct a pinhole camera looking from eye position towards a target.
// fovDegrees is the VERTICAL field of view angle in degrees.
// aspect is the width/height ratio of the image plane (e.g., 1920/1080 = 1.778).
__host__ inline Camera makeCamera(const vec3& eye, const vec3& target,
                                  float fovDegrees, float aspect)
{
    // World up direction (defines "vertical" in the world)
    const vec3 worldUp(0.0f, 1.0f, 0.0f);

    // Convert vertical FOV from degrees to radians and compute image plane half-dimensions
    float theta      = fovDegrees * 3.14159265f / 180.0f;
    float halfHeight = tanf(theta * 0.5f);  // Half-height based on FOV
    float halfWidth  = aspect * halfHeight; // Width scaled by aspect ratio

    // Build an orthonormal basis for the camera:
    // - w points AWAY from the target (backward along view direction)
    // - u points RIGHT (perpendicular to view direction)
    // - v points UP (perpendicular to both w and u)
    vec3 w = normalize(eye - target);              // Backward vector
    vec3 u = normalize(cross(worldUp, w));         // Right vector
    vec3 v = cross(w, u);                          // Up vector

    // Construct the camera with image plane in front of the eye
    Camera cam;
    cam.origin     = eye;
    // lowerLeft = eye - (right * halfWidth) - (up * halfHeight) - w
    // This positions the plane at distance 1 in front of the eye
    cam.lowerLeft  = eye - u * halfWidth - v * halfHeight - w;
    cam.horizontal = u * (2.0f * halfWidth);   // Full width of image plane
    cam.vertical   = v * (2.0f * halfHeight);  // Full height of image plane
    return cam;
}

// Construct an orbit camera: places the camera on a sphere around the target.
// This gives an interactive "examine object" viewing mode.
// yaw (horizontal angle) and pitch (vertical angle) rotate the camera position on the sphere.
// distance is the radius of the sphere (how far the camera is from the target).
__host__ inline Camera makeOrbitCamera(const vec3& target, float yaw, float pitch,
                                       float distance, float fovDegrees, float aspect)
{
    // Compute camera position on sphere using spherical coordinates:
    // x = distance * cos(pitch) * sin(yaw)
    // y = distance * sin(pitch)
    // z = distance * cos(pitch) * cos(yaw)
    vec3 offset(distance * cosf(pitch) * sinf(yaw),
                distance * sinf(pitch),
                distance * cosf(pitch) * cosf(yaw));
    // Place the camera at (target + offset) looking back at the target
    return makeCamera(target + offset, target, fovDegrees, aspect);
}

// Generate a ray through a pixel on the image plane.
// s is the normalized x-coordinate [0, 1] (left to right)
// t is the normalized y-coordinate [0, 1] (bottom to top)
// Returns a ray from the camera origin through the corresponding pixel.
__host__ __device__ inline Ray cameraRay(const Camera& cam, float s, float t) {
    // Compute the point on the image plane:
    // point = lowerLeft + s*horizontal + t*vertical
    // This interpolates between the four corners of the image plane
    vec3 point = cam.lowerLeft + cam.horizontal * s + cam.vertical * t;
    // Create and return a ray from the camera origin through this point
    return Ray(cam.origin, point - cam.origin);
}

#endif // CAMERA_H
