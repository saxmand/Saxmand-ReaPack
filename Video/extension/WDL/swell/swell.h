// Minimal stand-in for WDL's swell.h: just the types sdk/reaper_plugin.h needs,
// so the extension builds without the full WDL/SWELL tree.
#pragma once

#include <stdint.h>
#include <stddef.h>

typedef struct HWND__ *HWND;
typedef struct HINSTANCE__ *HINSTANCE;
typedef struct HMENU__ *HMENU;
typedef struct HDC__ *HDC;
typedef struct HICON__ *HICON;
typedef struct HFONT__ *HFONT;
typedef void *HANDLE;

typedef int64_t INT64;
typedef uint64_t UINT64;
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef intptr_t LPARAM;
typedef uintptr_t WPARAM;
typedef intptr_t LRESULT;
typedef unsigned int UINT;
typedef unsigned int DWORD;
typedef unsigned short WORD;
typedef unsigned char BYTE;
#include <objc/objc.h> // BOOL must match Objective-C (bool on arm64), as in SWELL
typedef char *LPSTR;
typedef const char *LPCSTR;

typedef struct { int left, top, right, bottom; } RECT;
typedef struct { int x, y; } POINT;
typedef struct { HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam; DWORD time; POINT pt; } MSG;
typedef struct { BYTE fVirt; WORD key; WORD cmd; } ACCEL;
typedef struct { unsigned int Data1; unsigned short Data2, Data3; unsigned char Data4[8]; } GUID;

typedef intptr_t LONG_PTR;
typedef HANDLE HDROP;
typedef struct { DWORD pFiles; POINT pt; BOOL fNC; BOOL fWide; } DROPFILES;

#define WM_DROPFILES 0x0233
#define GWL_WNDPROC (-4)

typedef LRESULT (*WNDPROC)(HWND, UINT, WPARAM, LPARAM);
typedef BOOL (*DLGPROC)(HWND, UINT, WPARAM, LPARAM);

#ifndef WINAPI
#define WINAPI
#endif
#ifndef CALLBACK
#define CALLBACK
#endif
