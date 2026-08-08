// main.cu — Win32 window + real-time CUDA render loop.
//
// No CMake. No OpenGL. No GLFW/SDL. No package manager.
// user32 and gdi32 are part of Windows itself and ship with the Visual Studio
// C++ workload that NVCC already requires.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <cstdio>
#include <cmath>

#include "vec3.h"
#include "ray.h"
#include "sphere.h"
#include "camera.h"
#include "renderer.h"

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------
static int  g_width   = 960;
static int  g_height  = 540;
static bool g_running = true;
static bool g_resized = true;   // forces the first allocation

// Camera: orbits the origin.
static float g_yaw   = 0.6f;    // radians, horizontal
static float g_pitch = 0.25f;   // radians, vertical
static float g_dist  = 7.0f;    // distance from the target

// Light: a movable glowing sphere.
static vec3  g_lightPos(3.0f, 3.5f, 2.0f);
static float g_lightPower = 2.2f;

// Mouse drag tracking
static bool g_dragging   = false;
static int  g_lastMouseX = 0;
static int  g_lastMouseY = 0;

// Buffers
static unsigned int* g_d_fb = nullptr;   // device (GPU)
static unsigned int* g_h_fb = nullptr;   // host (CPU), fed straight to GDI

static BITMAPINFO g_bmi;

// ---------------------------------------------------------------------------
// Allocate (or reallocate) the framebuffers for the current window size.
// ---------------------------------------------------------------------------
static bool resizeBuffers(int width, int height)
{
    if (g_d_fb) { cudaFree(g_d_fb);   g_d_fb = nullptr; }
    if (g_h_fb) { free(g_h_fb);       g_h_fb = nullptr; }

    size_t bytes = (size_t)width * height * sizeof(unsigned int);

    cudaError_t err = cudaMalloc((void**)&g_d_fb, bytes);
    if (err != cudaSuccess) {
        printf("cudaMalloc failed: %s\n", cudaGetErrorString(err));
        return false;
    }

    g_h_fb = (unsigned int*)malloc(bytes);
    if (!g_h_fb) {
        printf("Host malloc failed\n");
        return false;
    }

    // Describe the pixel layout to GDI.
    ZeroMemory(&g_bmi, sizeof(g_bmi));
    g_bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    g_bmi.bmiHeader.biWidth       = width;
    g_bmi.bmiHeader.biHeight      = -height;   // negative = top-down rows
    g_bmi.bmiHeader.biPlanes      = 1;
    g_bmi.bmiHeader.biBitCount    = 32;
    g_bmi.bmiHeader.biCompression = BI_RGB;

    return true;
}

// ---------------------------------------------------------------------------
// Build the scene for this frame.
// ---------------------------------------------------------------------------
static Scene buildScene()
{
    Scene scene;

    // Ground: an enormous sphere. Its top looks flat, so it reads as a floor.
    scene.spheres[scene.count++] =
        Sphere(vec3(0.0f, -1000.5f, 0.0f), 1000.0f, vec3(0.55f, 0.55f, 0.58f));

    // Main object.
    scene.spheres[scene.count++] =
        Sphere(vec3(0.0f, 0.0f, 0.0f), 1.0f, vec3(0.85f, 0.25f, 0.25f));

    // Companion object.
    scene.spheres[scene.count++] =
        Sphere(vec3(-1.9f, -0.15f, -0.5f), 0.35f, vec3(0.25f, 0.45f, 0.9f));

    // The light itself, drawn as a small emissive ball.
    scene.spheres[scene.count++] =
        Sphere(g_lightPos, 0.12f, vec3(1.0f, 0.95f, 0.75f), true);

    scene.lightPos   = g_lightPos;
    scene.lightColor = vec3(1.0f, 0.95f, 0.85f);
    scene.lightPower = g_lightPower;

    return scene;
}

// ---------------------------------------------------------------------------
// Continuous keyboard input, polled once per frame so held keys work smoothly.
// ---------------------------------------------------------------------------
static void handleInput(float dt)
{
    const float orbitSpeed = 1.6f;   // radians per second
    const float zoomSpeed  = 5.0f;
    const float lightSpeed = 4.0f;

    // Camera orbit
    if (GetAsyncKeyState(VK_LEFT)  & 0x8000) g_yaw   -= orbitSpeed * dt;
    if (GetAsyncKeyState(VK_RIGHT) & 0x8000) g_yaw   += orbitSpeed * dt;
    if (GetAsyncKeyState(VK_UP)    & 0x8000) g_pitch += orbitSpeed * dt;
    if (GetAsyncKeyState(VK_DOWN)  & 0x8000) g_pitch -= orbitSpeed * dt;

    // Zoom
    if (GetAsyncKeyState('W') & 0x8000) g_dist -= zoomSpeed * dt;
    if (GetAsyncKeyState('S') & 0x8000) g_dist += zoomSpeed * dt;

    // Light movement
    if (GetAsyncKeyState('I') & 0x8000) g_lightPos.z -= lightSpeed * dt;
    if (GetAsyncKeyState('K') & 0x8000) g_lightPos.z += lightSpeed * dt;
    if (GetAsyncKeyState('J') & 0x8000) g_lightPos.x -= lightSpeed * dt;
    if (GetAsyncKeyState('L') & 0x8000) g_lightPos.x += lightSpeed * dt;
    if (GetAsyncKeyState('U') & 0x8000) g_lightPos.y += lightSpeed * dt;
    if (GetAsyncKeyState('O') & 0x8000) g_lightPos.y -= lightSpeed * dt;

    // Light brightness
    if (GetAsyncKeyState(VK_OEM_PLUS)  & 0x8000) g_lightPower += 2.0f * dt;
    if (GetAsyncKeyState(VK_OEM_MINUS) & 0x8000) g_lightPower -= 2.0f * dt;

    // Keep everything in sane ranges.
    if (g_pitch >  1.45f) g_pitch =  1.45f;
    if (g_pitch < -0.20f) g_pitch = -0.20f;
    if (g_dist  <  2.0f)  g_dist  =  2.0f;
    if (g_dist  > 30.0f)  g_dist  = 30.0f;
    if (g_lightPower < 0.1f) g_lightPower = 0.1f;
}

// ---------------------------------------------------------------------------
// Window message handler
// ---------------------------------------------------------------------------
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {

    case WM_DESTROY:
        g_running = false;
        PostQuitMessage(0);
        return 0;

    case WM_SIZE: {
        int w = LOWORD(lParam);
        int h = HIWORD(lParam);
        if (w > 0 && h > 0 && (w != g_width || h != g_height)) {
            g_width   = w;
            g_height  = h;
            g_resized = true;
        }
        return 0;
    }

    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            g_running = false;
        } else if (wParam == 'R') {           // reset view
            g_yaw   = 0.6f;
            g_pitch = 0.25f;
            g_dist  = 7.0f;
            g_lightPos   = vec3(3.0f, 3.5f, 2.0f);
            g_lightPower = 2.2f;
        }
        return 0;

    case WM_LBUTTONDOWN:
        g_dragging   = true;
        g_lastMouseX = LOWORD(lParam);
        g_lastMouseY = HIWORD(lParam);
        SetCapture(hwnd);
        return 0;

    case WM_LBUTTONUP:
        g_dragging = false;
        ReleaseCapture();
        return 0;

    case WM_MOUSEMOVE:
        if (g_dragging) {
            int mx = (short)LOWORD(lParam);
            int my = (short)HIWORD(lParam);
            g_yaw   += (mx - g_lastMouseX) * 0.008f;
            g_pitch += (my - g_lastMouseY) * 0.008f;
            g_lastMouseX = mx;
            g_lastMouseY = my;
        }
        return 0;

    case WM_MOUSEWHEEL: {
        int delta = GET_WHEEL_DELTA_WPARAM(wParam);
        g_dist -= (delta / 120.0f) * 0.5f;
        return 0;
    }

    // We repaint every frame in the main loop, so tell Windows not to erase
    // the background (that would cause flicker).
    case WM_ERASEBKGND:
        return 1;
    }

    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
int main()
{
    // ---- Create the window -------------------------------------------------
    HINSTANCE hInstance = GetModuleHandle(nullptr);

    WNDCLASS wc = {};
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInstance;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = "CudaRayTracerWindow";

    if (!RegisterClass(&wc)) {
        printf("RegisterClass failed\n");
        return 1;
    }

    // Grow the window so the CLIENT area is exactly g_width x g_height.
    RECT rect = { 0, 0, g_width, g_height };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hwnd = CreateWindow(
        wc.lpszClassName, "CUDA Ray Tracer",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        rect.right - rect.left, rect.bottom - rect.top,
        nullptr, nullptr, hInstance, nullptr);

    if (!hwnd) {
        printf("CreateWindow failed\n");
        return 1;
    }

    ShowWindow(hwnd, SW_SHOW);

    printf("Controls\n");
    printf("  Drag mouse / arrow keys : orbit camera\n");
    printf("  Mouse wheel, W / S      : zoom\n");
    printf("  I J K L                 : move light horizontally\n");
    printf("  U / O                   : move light up / down\n");
    printf("  + / -                   : light brightness\n");
    printf("  R                       : reset\n");
    printf("  Esc                     : quit\n\n");

    // ---- Timing ------------------------------------------------------------
    LARGE_INTEGER freq, prev;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&prev);

    float fpsTimer  = 0.0f;
    int   fpsFrames = 0;

    // ---- Main loop ---------------------------------------------------------
    while (g_running) {

        MSG msg;
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) g_running = false;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        if (!g_running) break;

        // Delta time
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        float dt = (float)(now.QuadPart - prev.QuadPart) / (float)freq.QuadPart;
        prev = now;
        if (dt > 0.1f) dt = 0.1f;   // don't let a stall teleport the camera

        // Reallocate if the window changed size
        if (g_resized) {
            if (!resizeBuffers(g_width, g_height)) break;
            g_resized = false;
        }

        handleInput(dt);

        // ---- Render one frame ---------------------------------------------
        float  aspect = (float)g_width / (float)g_height;
        Camera cam    = makeOrbitCamera(vec3(0.0f, 0.0f, 0.0f),
                                        g_yaw, g_pitch, g_dist, 45.0f, aspect);
        Scene  scene  = buildScene();

        renderFrame(g_d_fb, g_width, g_height, cam, scene);

        cudaError_t err = cudaMemcpy(g_h_fb, g_d_fb,
                                     (size_t)g_width * g_height * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost);
        if (err != cudaSuccess) {
            printf("cudaMemcpy failed: %s\n", cudaGetErrorString(err));
            break;
        }

        // ---- Blit the pixels to the window --------------------------------
        HDC hdc = GetDC(hwnd);
        StretchDIBits(hdc,
                      0, 0, g_width, g_height,     // destination
                      0, 0, g_width, g_height,     // source
                      g_h_fb, &g_bmi, DIB_RGB_COLORS, SRCCOPY);
        ReleaseDC(hwnd, hdc);

        // ---- FPS in the title bar -----------------------------------------
        fpsFrames++;
        fpsTimer += dt;
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

    // ---- Cleanup -----------------------------------------------------------
    if (g_d_fb) cudaFree(g_d_fb);
    if (g_h_fb) free(g_h_fb);

    return 0;
}
