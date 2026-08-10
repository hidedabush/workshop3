// main.cu — Win32 window + real-time CUDA render loop.
//
// No CMake. No OpenGL. No GLFW/SDL. No package manager.
// user32 and gdi32 are part of Windows itself and ship with the Visual Studio
// C++ workload that NVCC already requires.

#define WIN32_LEAN_AND_MEAN  // Exclude rarely-used Windows APIs to reduce compile time
#define NOMINMAX             // Don't define min/max macros; let std handle them
#include <windows.h>         // Windows API for window creation and GDI rendering

#include <cstdio>   // printf for console output
#include <cmath>    // Math functions (used in camera/ray calculations)

#include "vec3.h"      // 3D vector math
#include "ray.h"       // Ray structure for ray tracing
#include "sphere.h"    // Sphere primitive geometry
#include "camera.h"    // Camera and view matrix calculations
#include "renderer.h"  // CUDA kernel launch and ray tracing pipeline

// ---------------------------------------------------------------------------
// Application state — window and rendering configuration
// ---------------------------------------------------------------------------
static int  g_width   = 960;          // Window client area width in pixels
static int  g_height  = 540;          // Window client area height in pixels
static bool g_running = true;         // False when user closes window
static bool g_resized = true;         // True when window is resized; triggers buffer reallocation

// Camera: orbits the origin (0, 0, 0). Spherical coordinates define the view.
static float g_yaw   = 0.6f;          // Horizontal rotation (left/right), radians
static float g_pitch = 0.25f;         // Vertical rotation (up/down), radians
static float g_dist  = 7.0f;          // Distance from camera to origin

// Light: a movable point light that emits light and is drawn as a small sphere.
static vec3  g_lightPos(3.0f, 3.5f, 2.0f);  // Position in world space
static float g_lightPower = 2.2f;           // Brightness multiplier

// Mouse drag tracking — used for camera orbit control
static bool g_dragging   = false;     // True while left mouse button is held
static int  g_lastMouseX = 0;         // Previous mouse X position during drag
static int  g_lastMouseY = 0;         // Previous mouse Y position during drag

// GPU/CPU framebuffer pair — pixels flow GPU → CPU → screen
static unsigned int* g_d_fb = nullptr;  // Device (GPU) framebuffer: rendered pixels live here
static unsigned int* g_h_fb = nullptr;  // Host (CPU) framebuffer: staging area before GDI display

static BITMAPINFO g_bmi;              // Windows GDI pixel format descriptor

// ---------------------------------------------------------------------------
// Allocate (or reallocate) GPU and CPU framebuffers for the current window size.
// ---------------------------------------------------------------------------
static bool resizeBuffers(int width, int height)
{
    // Free old buffers if they exist
    if (g_d_fb) { cudaFree(g_d_fb);   g_d_fb = nullptr; }
    if (g_h_fb) { free(g_h_fb);       g_h_fb = nullptr; }

    // Calculate total memory needed: width * height * 4 bytes per RGBA pixel
    size_t bytes = (size_t)width * height * sizeof(unsigned int);

    // Allocate GPU memory for the rendered framebuffer
    cudaError_t err = cudaMalloc((void**)&g_d_fb, bytes);
    if (err != cudaSuccess) {
        printf("cudaMalloc failed: %s\n", cudaGetErrorString(err));
        return false;
    }

    // Allocate CPU memory as a staging buffer for copying pixels from GPU to screen
    g_h_fb = (unsigned int*)malloc(bytes);
    if (!g_h_fb) {
        printf("Host malloc failed\n");
        return false;
    }

    // Configure Windows GDI pixel format descriptor (BITMAPINFO)
    // This tells Windows how to interpret the pixel data when drawing to the window
    ZeroMemory(&g_bmi, sizeof(g_bmi));
    g_bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    g_bmi.bmiHeader.biWidth       = width;
    g_bmi.bmiHeader.biHeight      = -height;   // Negative height means top-down (standard Windows format)
    g_bmi.bmiHeader.biPlanes      = 1;         // Single color plane (not used for RGB)
    g_bmi.bmiHeader.biBitCount    = 32;        // 32 bits per pixel (RGBA)
    g_bmi.bmiHeader.biCompression = BI_RGB;    // No compression

    return true;
}

// ---------------------------------------------------------------------------
// Construct the ray-traced scene for this frame.
// Creates spheres at specific positions/sizes and assigns their material colors.
// ---------------------------------------------------------------------------
static Scene buildScene()
{
    Scene scene;

    // Create floor: an enormous sphere positioned far below the origin.
    // The top surface appears flat because the sphere is so large.
    scene.spheres[scene.count++] =
        Sphere(vec3(0.0f, -1000.5f, 0.0f), 1000.0f, vec3(0.55f, 0.55f, 0.58f));

    // Create main object: a red sphere at the origin.
    scene.spheres[scene.count++] =
        Sphere(vec3(0.0f, 0.0f, 0.0f), 1.0f, vec3(0.85f, 0.25f, 0.25f));

    // Create companion object: a blue sphere offset to the left and slightly down.
    scene.spheres[scene.count++] =
        Sphere(vec3(-1.9f, -0.15f, -0.5f), 0.35f, vec3(0.25f, 0.45f, 0.9f));

    // Create light source: a small glowing ball at g_lightPos.
    // The final 'true' parameter marks this sphere as emissive (the light).
    scene.spheres[scene.count++] =
        Sphere(g_lightPos, 0.12f, vec3(1.0f, 0.95f, 0.75f), true);

    // Store light parameters that the ray tracer will use for shading
    scene.lightPos   = g_lightPos;      // Position of the point light
    scene.lightColor = vec3(1.0f, 0.95f, 0.85f);  // RGB color of light (warm white)
    scene.lightPower = g_lightPower;    // Intensity multiplier

    return scene;
}

// ---------------------------------------------------------------------------
// Poll keyboard input every frame (asynchronous) so held keys feel responsive.
// Updates camera orbit, zoom, and light position based on which keys are pressed.
// ---------------------------------------------------------------------------
static void handleInput(float dt)
{
    // Speed constants (scaled by dt to be framerate-independent)
    const float orbitSpeed = 1.6f;   // Camera rotation speed (radians per second)
    const float zoomSpeed  = 5.0f;   // Zoom speed (units per second)
    const float lightSpeed = 4.0f;   // Light movement speed (units per second)

    // GetAsyncKeyState(key) & 0x8000 checks if key is currently held down
    // (non-zero means pressed, 0x8000 bit indicates key was pressed since last call)

    // Camera orbit control using arrow keys
    if (GetAsyncKeyState(VK_LEFT)  & 0x8000) g_yaw   -= orbitSpeed * dt;  // Rotate left
    if (GetAsyncKeyState(VK_RIGHT) & 0x8000) g_yaw   += orbitSpeed * dt;  // Rotate right
    if (GetAsyncKeyState(VK_UP)    & 0x8000) g_pitch += orbitSpeed * dt;  // Rotate up
    if (GetAsyncKeyState(VK_DOWN)  & 0x8000) g_pitch -= orbitSpeed * dt;  // Rotate down

    // Zoom in/out using W and S keys
    if (GetAsyncKeyState('W') & 0x8000) g_dist -= zoomSpeed * dt;  // Zoom in (decrease distance)
    if (GetAsyncKeyState('S') & 0x8000) g_dist += zoomSpeed * dt;  // Zoom out (increase distance)

    // Light movement using IJKL keys (like arrow keys but for left/right/back/forward)
    if (GetAsyncKeyState('I') & 0x8000) g_lightPos.z -= lightSpeed * dt;  // Move light forward
    if (GetAsyncKeyState('K') & 0x8000) g_lightPos.z += lightSpeed * dt;  // Move light backward
    if (GetAsyncKeyState('J') & 0x8000) g_lightPos.x -= lightSpeed * dt;  // Move light left
    if (GetAsyncKeyState('L') & 0x8000) g_lightPos.x += lightSpeed * dt;  // Move light right
    if (GetAsyncKeyState('U') & 0x8000) g_lightPos.y += lightSpeed * dt;  // Move light up
    if (GetAsyncKeyState('O') & 0x8000) g_lightPos.y -= lightSpeed * dt;  // Move light down

    // Light brightness using + and - keys
    if (GetAsyncKeyState(VK_OEM_PLUS)  & 0x8000) g_lightPower += 2.0f * dt;  // Increase brightness
    if (GetAsyncKeyState(VK_OEM_MINUS) & 0x8000) g_lightPower -= 2.0f * dt;  // Decrease brightness

    // Clamp values to sensible ranges to prevent strange camera/light behavior
    if (g_pitch >  1.45f) g_pitch =  1.45f;   // Prevent looking too far up
    if (g_pitch < -0.20f) g_pitch = -0.20f;   // Prevent looking too far down
    if (g_dist  <  2.0f)  g_dist  =  2.0f;    // Minimum zoom distance
    if (g_dist  > 30.0f)  g_dist  = 30.0f;    // Maximum zoom distance
    if (g_lightPower < 0.1f) g_lightPower = 0.1f;  // Minimum light brightness
}

// ---------------------------------------------------------------------------
// Window message handler — responds to events like resizing, keyboard, and mouse input.
// ---------------------------------------------------------------------------
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {

    case WM_DESTROY:
        // Window is being destroyed; exit the main loop
        g_running = false;
        PostQuitMessage(0);
        return 0;

    case WM_SIZE: {
        // Window was resized; extract new dimensions and flag for buffer reallocation
        int w = LOWORD(lParam);  // New width from LPARAM
        int h = HIWORD(lParam);  // New height from LPARAM
        if (w > 0 && h > 0 && (w != g_width || h != g_height)) {
            g_width   = w;
            g_height  = h;
            g_resized = true;  // Signal main loop to reallocate framebuffers
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            // Escape key: exit the application
            g_running = false;
        } else if (wParam == 'R') {
            // R key: reset camera and light to their default positions
            g_yaw   = 0.6f;
            g_pitch = 0.25f;
            g_dist  = 7.0f;
            g_lightPos   = vec3(3.0f, 3.5f, 2.0f);
            g_lightPower = 2.2f;
        }
        return 0;

    case WM_LBUTTONDOWN:
        // Left mouse button pressed: start dragging to orbit the camera
        g_dragging   = true;
        g_lastMouseX = LOWORD(lParam);   // Record starting mouse position
        g_lastMouseY = HIWORD(lParam);
        SetCapture(hwnd);  // Capture mouse even if cursor leaves window
        return 0;

    case WM_LBUTTONUP:
        // Left mouse button released: stop dragging
        g_dragging = false;
        ReleaseCapture();  // Stop capturing mouse events
        return 0;

    case WM_MOUSEMOVE:
        // Mouse moved; if dragging, rotate the camera based on delta
        if (g_dragging) {
            int mx = (short)LOWORD(lParam);  // Current mouse X
            int my = (short)HIWORD(lParam);  // Current mouse Y
            // Convert pixel delta to angle delta (0.008 radians per pixel)
            g_yaw   += (mx - g_lastMouseX) * 0.008f;
            g_pitch += (my - g_lastMouseY) * 0.008f;
            g_lastMouseX = mx;
            g_lastMouseY = my;
        }
        return 0;

    case WM_MOUSEWHEEL: {
        // Mouse wheel: zoom in/out (delta is +120 or -120)
        int delta = GET_WHEEL_DELTA_WPARAM(wParam);
        g_dist -= (delta / 120.0f) * 0.5f;  // Each wheel notch adjusts distance by 0.5 units
        return 0;
    }

    case WM_ERASEBKGND:
        // We render every frame in the main loop, so prevent Windows from
        // clearing the background (it would cause visible flicker).
        return 1;
    }

    // Unhandled messages go to the default Windows handler
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Main entry point — creates the window and runs the render loop
// ---------------------------------------------------------------------------
int main()
{
    // ---- Create the window -------------------------------------------------
    // Get the application instance handle
    HINSTANCE hInstance = GetModuleHandle(nullptr);

    // Define the window class
    WNDCLASS wc = {};
    wc.lpfnWndProc   = WndProc;                    // Message handler callback
    wc.hInstance     = hInstance;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = "CudaRayTracerWindow";

    // Register the window class with Windows
    if (!RegisterClass(&wc)) {
        printf("RegisterClass failed\n");
        return 1;
    }

    // Calculate the window size needed so the CLIENT area (drawable region)
    // is exactly g_width x g_height (AdjustWindowRect adds frame/title bar)
    RECT rect = { 0, 0, g_width, g_height };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

    // Create the window
    HWND hwnd = CreateWindow(
        wc.lpszClassName, "CUDA Ray Tracer",
        WS_OVERLAPPEDWINDOW,  // Standard window with title bar, resize handles, etc.
        CW_USEDEFAULT, CW_USEDEFAULT,  // Let Windows choose position
        rect.right - rect.left, rect.bottom - rect.top,  // Total window size
        nullptr, nullptr, hInstance, nullptr);

    if (!hwnd) {
        printf("CreateWindow failed\n");
        return 1;
    }

    ShowWindow(hwnd, SW_SHOW);

    // Print control instructions to console
    printf("Controls\n");
    printf("  Drag mouse / arrow keys : orbit camera\n");
    printf("  Mouse wheel, W / S      : zoom\n");
    printf("  I J K L                 : move light horizontally\n");
    printf("  U / O                   : move light up / down\n");
    printf("  + / -                   : light brightness\n");
    printf("  R                       : reset\n");
    printf("  Esc                     : quit\n\n");

    // ---- Timing setup ------------------------------------------------------
    // Use Windows' high-resolution timer for accurate frame timing
    LARGE_INTEGER freq, prev;
    QueryPerformanceFrequency(&freq);  // Frequency of the performance counter
    QueryPerformanceCounter(&prev);    // Current time

    float fpsTimer  = 0.0f;  // Accumulates dt for FPS calculation
    int   fpsFrames = 0;     // Frame counter for FPS display

    // ---- Main render loop --------------------------------------------------
    while (g_running) {

        // Process all pending Windows messages (keyboard, mouse, window events)
        MSG msg;
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) g_running = false;
            TranslateMessage(&msg);  // Translate virtual key codes
            DispatchMessage(&msg);   // Send message to WndProc
        }
        if (!g_running) break;

        // ---- Calculate frame delta time (framerate-independent) -------
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        // Convert counter ticks to seconds
        float dt = (float)(now.QuadPart - prev.QuadPart) / (float)freq.QuadPart;
        prev = now;
        // Clamp dt to prevent huge jumps if the app stalls (e.g., on breakpoint)
        if (dt > 0.1f) dt = 0.1f;

        // ---- Reallocate GPU/CPU buffers if window was resized --------
        if (g_resized) {
            if (!resizeBuffers(g_width, g_height)) break;
            g_resized = false;
        }

        // ---- Process user input ----------------------------------------
        handleInput(dt);

        // ---- Render the scene to the GPU framebuffer ------------------
        float  aspect = (float)g_width / (float)g_height;
        // Build camera from orbit parameters (yaw, pitch, distance)
        Camera cam    = makeOrbitCamera(vec3(0.0f, 0.0f, 0.0f),
                                        g_yaw, g_pitch, g_dist, 45.0f, aspect);
        // Build the scene (spheres and light)
        Scene  scene  = buildScene();

        // Launch CUDA kernel to trace rays and fill g_d_fb with pixel colors
        renderFrame(g_d_fb, g_width, g_height, cam, scene);

        // ---- Copy rendered pixels from GPU to CPU ---------------------
        // Transfer the GPU framebuffer to CPU memory for display
        cudaError_t err = cudaMemcpy(g_h_fb, g_d_fb,
                                     (size_t)g_width * g_height * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost);
        if (err != cudaSuccess) {
            printf("cudaMemcpy failed: %s\n", cudaGetErrorString(err));
            break;
        }

        // ---- Display pixels on screen via Windows GDI ----------------
        // Get a device context (drawing surface) for the window
        HDC hdc = GetDC(hwnd);
        // Copy the framebuffer to the window using DIB (Device Independent Bitmap)
        StretchDIBits(hdc,
                      0, 0, g_width, g_height,     // destination rectangle
                      0, 0, g_width, g_height,     // source rectangle
                      g_h_fb, &g_bmi, DIB_RGB_COLORS, SRCCOPY);
        ReleaseDC(hwnd, hdc);

        // ---- Update FPS counter in window title bar -------------------
        fpsFrames++;
        fpsTimer += dt;
        // Every ~0.5 seconds, update the title bar with current FPS
        if (fpsTimer >= 0.5f) {
            char title[128];
            sprintf_s(title, sizeof(title),
                      "CUDA Ray Tracer  -  %dx%d  -  %.0f FPS",
                      g_width, g_height, fpsFrames / fpsTimer);
            SetWindowText(hwnd, title);
            fpsFrames = 0;
            fpsTimer  = 0.0f;
        }
    }

    // ---- Cleanup GPU and CPU resources --------------------------------
    if (g_d_fb) cudaFree(g_d_fb);
    if (g_h_fb) free(g_h_fb);

    return 0;
}
