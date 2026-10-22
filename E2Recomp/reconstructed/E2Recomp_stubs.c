#include "E2Recomp_recon.h"
#include <stdarg.h>

#undef CreateWindowExA
#undef DialogBoxParamA

uintptr_t E2R_timer_slots[8];

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dst;
}

static LONG __stdcall E2R_CrashFilter(struct _EXCEPTION_POINTERS *info) {
    char buffer[512];
    DWORD written;
    HANDLE f = CreateFileA("E2Recomp_rebuilt_crash.log", GENERIC_WRITE, FILE_SHARE_READ, NULL,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f != INVALID_HANDLE_VALUE) {
#if defined(_M_IX86)
        wsprintfA(buffer,
                  "ModuleBase=0x%08lx\r\nExceptionCode=0x%08lx\r\nExceptionAddress=0x%08lx\r\nEIP=0x%08lx\r\nESP=0x%08lx\r\nEAX=0x%08lx EBX=0x%08lx ECX=0x%08lx EDX=0x%08lx\r\nSTACK=0x%08lx 0x%08lx 0x%08lx 0x%08lx 0x%08lx 0x%08lx\r\n",
                  (DWORD)(uintptr_t)GetModuleHandleA(NULL),
                  info->ExceptionRecord->ExceptionCode,
                  (DWORD)(uintptr_t)info->ExceptionRecord->ExceptionAddress,
                  info->ContextRecord->Eip,
                  info->ContextRecord->Esp,
                  info->ContextRecord->Eax, info->ContextRecord->Ebx,
                  info->ContextRecord->Ecx, info->ContextRecord->Edx,
                  ((DWORD *)info->ContextRecord->Esp)[0],
                  ((DWORD *)info->ContextRecord->Esp)[1],
                  ((DWORD *)info->ContextRecord->Esp)[2],
                  ((DWORD *)info->ContextRecord->Esp)[3],
                  ((DWORD *)info->ContextRecord->Esp)[4],
                  ((DWORD *)info->ContextRecord->Esp)[5]);
#else
        wsprintfA(buffer, "ExceptionCode=0x%08lx\r\nExceptionAddress=%p\r\n",
                  info->ExceptionRecord->ExceptionCode,
                  info->ExceptionRecord->ExceptionAddress);
#endif
        WriteFile(f, buffer, lstrlenA(buffer), &written, NULL);
        CloseHandle(f);
    }
    return EXCEPTION_EXECUTE_HANDLER;
}

void E2R_InstallCrashHandler(void) {
    SetUnhandledExceptionFilter(E2R_CrashFilter);
    VirtualAlloc((LPVOID)0x00400000, 0x00100000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    VirtualAlloc((LPVOID)0x00600000, 0x00100000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    VirtualAlloc((LPVOID)0x00700000, 0x00200000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    VirtualAlloc((LPVOID)0x00900000, 0x00100000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    VirtualAlloc((LPVOID)0x00a00000, 0x00100000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
}

/* FUN_0041007c faults on a Ghidra register artifact. Run it on its own thread and
   end that thread on an access violation so the process, and the window created
   by FUN_00458714, survive. This image does not link the CRT, so __try is unavailable. */
static volatile DWORD E2R_game_thread_id;

static LONG CALLBACK E2R_GameFaultHandler(struct _EXCEPTION_POINTERS *info) {
    DWORD code = info->ExceptionRecord->ExceptionCode;
    if (E2R_game_thread_id != 0 && GetCurrentThreadId() == E2R_game_thread_id &&
        (code == EXCEPTION_ACCESS_VIOLATION || code == EXCEPTION_ILLEGAL_INSTRUCTION)) {
        ExitThread(1);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static DWORD WINAPI E2R_RunGameInit(LPVOID unused) {
    (void)unused;
    FUN_0041007c(0);
    return 0;
}

/* The real CreateWindow is a borderless fullscreen popup. Nothing paints it, and
   the decompiled game start faults before the message loop, so give that same
   HWND a title bar the user can see and close. */
static void E2R_EnsureVisibleWindow(void) {
    HWND hwnd = (HWND)_DAT_00ac4dac;
    HINSTANCE inst = GetModuleHandleA(NULL);

    if (!IsWindow(hwnd)) {
        WNDCLASSA wc;
        wc.style = 3;
        wc.lpfnWndProc = E2R_WndProc;
        wc.cbClsExtra = 0;
        wc.cbWndExtra = 0;
        wc.hInstance = inst;
        wc.hIcon = LoadIconA(NULL, (LPCSTR)0x7f00);
        wc.hCursor = LoadCursorA(NULL, (LPCSTR)0x7f00);
        wc.hbrBackground = (HBRUSH)GetStockObject(4);
        wc.lpszMenuName = NULL;
        wc.lpszClassName = "Ecstatica2";
        RegisterClassA(&wc);
        hwnd = CreateWindowExA(0, "Ecstatica2", "Ecstatica II",
                                WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                                CW_USEDEFAULT, CW_USEDEFAULT, 960, 720,
                                NULL, NULL, inst, NULL);
        _DAT_00ac4dac = (uintptr_t)hwnd;
    } else {
        LONG style = GetWindowLongA(hwnd, GWL_STYLE);
        LONG ex = GetWindowLongA(hwnd, GWL_EXSTYLE);
        SetWindowLongA(hwnd, GWL_STYLE, (style & ~WS_POPUP) | WS_OVERLAPPEDWINDOW | WS_VISIBLE);
        SetWindowLongA(hwnd, GWL_EXSTYLE, ex & ~WS_EX_TOPMOST);
        SetWindowPos(hwnd, HWND_NOTOPMOST, 80, 80, 960, 720,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    }
    hwnd = (HWND)_DAT_00ac4dac;
    if (IsWindow(hwnd)) {
        ShowWindow(hwnd, SW_SHOWNORMAL);
        UpdateWindow(hwnd);
        SetForegroundWindow(hwnd);
    }
}

void E2R_WinMainThunk(void) {
    MSG msg;
    _DAT_00ac4d90 = (uintptr_t)GetModuleHandleA(NULL);
    if (FUN_00458714() != 0) {
        HANDLE thread;
        DWORD tid = 0;
        PVOID veh;
        FUN_0041ba68(0, 0);
        veh = AddVectoredExceptionHandler(1, E2R_GameFaultHandler);
        thread = CreateThread(NULL, 0, E2R_RunGameInit, NULL, CREATE_SUSPENDED, &tid);
        if (thread) {
            E2R_game_thread_id = tid;
            ResumeThread(thread);
            if (WaitForSingleObject(thread, 3000) == WAIT_TIMEOUT) {
                SuspendThread(thread);
            }
            CloseHandle(thread);
        }
        E2R_game_thread_id = 0;
        if (veh) RemoveVectoredExceptionHandler(veh);
    }
    ShowCursor(TRUE);
    E2R_EnsureVisibleWindow();
    while (IsWindow((HWND)_DAT_00ac4dac)) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) return;
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        Sleep(16);
    }
}

LRESULT CALLBACK E2R_WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hWnd, msg, wParam, lParam);
}

int in(unsigned short port) { (void)port; return 0; }
void out(unsigned short port, unsigned int value) { (void)port; (void)value; }

double fpatan(double a, double b) { (void)b; return a; }
double fptan(double a) { return a; }
int ROUND(double value) { return (int)value; }
void halt_baddata(void) {}

unsigned __int64 ZEXT48(unsigned int value) { return value; }
unsigned __int64 CONCAT24(unsigned short hi, unsigned int lo) { return (((unsigned __int64)hi) << 32) | lo; }
unsigned __int64 CONCAT28(unsigned short hi, unsigned __int64 lo) { return (((unsigned __int64)hi) << 48) | (lo & 0x0000ffffffffffffULL); }
unsigned int SUB84(unsigned __int64 value, unsigned int offset) { return (unsigned int)(value >> (offset * 8)); }
unsigned int SUB104(unkuint10 value, unsigned int offset) { return (unsigned int)(value >> (offset * 8)); }
int CARRY1(unsigned char a, unsigned char b) { return (unsigned int)a + (unsigned int)b > 0xffu; }
int CARRY4(unsigned int a, unsigned int b) { return (unsigned __int64)a + (unsigned __int64)b > 0xffffffffULL; }
int ABS(int value) { return value < 0 ? -value : value; }
void LOCK(void) {}
void UNLOCK(void) {}
void swi(unsigned int interrupt_id) { (void)interrupt_id; }

double NAN = 0.0;
uintptr_t LocalDescriptorTableRegister = 0;
int _except1 = 0;

void func_0x0045cf39(void) {}
void func_0x0045d839(void) {}
void func_0x0045d7c4(void) {}
void func_0x0045d10e(void) {}
void func_0x0045d5f8(void) {}
void func_0x0045d482(void) {}
void func_0x0045d92a(void) {}
void func_0x0045dab9(void) {}
void func_0x0045db21(void) {}
void func_0x0045dbba(void) {}
void func_0x0000023b(void) {}
void func_0x012eb116(void) {}

HWND E2R_CreateWindowExA(DWORD exStyle, ...) {
    va_list ap;
    LPCSTR className;
    LPCSTR windowName;
    DWORD style;
    int x, y, width, height;
    HWND parent;
    HMENU menu;
    HINSTANCE instance;
    LPVOID param;

    va_start(ap, exStyle);
    className = va_arg(ap, LPCSTR);
    windowName = va_arg(ap, LPCSTR);
    style = va_arg(ap, DWORD);
    x = va_arg(ap, int);
    y = va_arg(ap, int);
    width = va_arg(ap, int);
    height = va_arg(ap, int);
    parent = va_arg(ap, HWND);
    menu = va_arg(ap, HMENU);
    instance = va_arg(ap, HINSTANCE);
    param = va_arg(ap, LPVOID);
    va_end(ap);

    return CreateWindowExA(exStyle, className, windowName, style, x, y, width, height, parent, menu, instance, param);
}

INT_PTR E2R_DialogBoxParamA(HINSTANCE inst, LPCSTR tmpl, HWND parent, DLGPROC proc, LPARAM param) {
    return DialogBoxParamA(inst, tmpl, parent, proc, param);
}

static void *E2R_dd_vtbl[64];
static void *E2R_dd_obj[1] = { E2R_dd_vtbl };
static void *E2R_surf_vtbl[64];
static void *E2R_surf_obj[1] = { E2R_surf_vtbl };

/* Vtable calls go through `typedef int code()`, and this build compiles those
   as cdecl: the caller pops however many arguments it pushed. A fixed
   __stdcall parameter list would `ret N` and pop them again. Varargs keep
   the COM argument list (unused ones are ignored) and leave that pop to the
   caller, so the stack stays balanced. */
static int __stdcall E2R_DD_Generic(void *self, ...) {
    (void)self;
    return 0;
}

static int __stdcall E2R_DD_CreateSurface(void *self, ...) {
    va_list ap;
    void *desc;
    void **out;
    void *outer;

    (void)self;
    va_start(ap, self);
    desc = va_arg(ap, void *);
    out = va_arg(ap, void **);
    outer = va_arg(ap, void *);
    va_end(ap);
    (void)desc;
    (void)outer;
    if (out) *out = E2R_surf_obj;
    return 0;
}

HRESULT DirectDrawCreate(void *guid, void **ddraw, void *outer) {
    int i;
    (void)guid;
    (void)outer;
    for (i = 0; i < 64; i++) {
        E2R_dd_vtbl[i] = (void *)E2R_DD_Generic;
        E2R_surf_vtbl[i] = (void *)E2R_DD_Generic;
    }
    E2R_dd_vtbl[6] = (void *)E2R_DD_CreateSurface;
    if (ddraw) *ddraw = E2R_dd_obj;
    return 0;
}

HRESULT DirectSoundCreate(void *guid, void **dsound, void *outer) {
    typedef HRESULT (WINAPI *DirectSoundCreateFn)(void *, void **, void *);
    static DirectSoundCreateFn fn;
    if (!fn) fn = (DirectSoundCreateFn)GetProcAddress(LoadLibraryA("dsound.dll"), "DirectSoundCreate");
    if (fn) return fn(guid, dsound, outer);
    if (dsound) *dsound = 0;
    return E_FAIL;
}

int acmMetrics(void) {
    typedef int (WINAPI *AcmMetricsFn)(void);
    static AcmMetricsFn fn;
    if (!fn) fn = (AcmMetricsFn)GetProcAddress(LoadLibraryA("msacm32.dll"), "acmMetrics");
    return fn ? fn() : 0;
}

short SIMD_InitDriver(unsigned int flags, GUID *guid, short device) {
    typedef short (WINAPI *Fn)(unsigned int, GUID *, short);
    static Fn fn;
    if (!fn) fn = (Fn)GetProcAddress(LoadLibraryA("SIMD_W95.DLL"), "SIMD_InitDriver");
    return fn ? fn(flags, guid, device) : 0;
}

short SIMD_PlayTune(char *path, short mode) {
    typedef short (WINAPI *Fn)(char *, short);
    static Fn fn;
    if (!fn) fn = (Fn)GetProcAddress(LoadLibraryA("SIMD_W95.DLL"), "SIMD_PlayTune");
    return fn ? fn(path, mode) : 0;
}

short SIMD_StopTune(void) {
    typedef short (WINAPI *Fn)(void);
    static Fn fn;
    if (!fn) fn = (Fn)GetProcAddress(LoadLibraryA("SIMD_W95.DLL"), "SIMD_StopTune");
    return fn ? fn() : 0;
}

short SIMD_RemoveDriver(void) {
    typedef short (WINAPI *Fn)(void);
    static Fn fn;
    if (!fn) fn = (Fn)GetProcAddress(LoadLibraryA("SIMD_W95.DLL"), "SIMD_RemoveDriver");
    return fn ? fn() : 0;
}
