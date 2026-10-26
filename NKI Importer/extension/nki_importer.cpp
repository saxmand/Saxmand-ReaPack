// NKI Importer - REAPER extension (macOS and Windows).
// Subclasses the arrange view and catches WM_DROPFILES before REAPER sees it:
//   * only .nki files dropped  -> swallowed, so no "Could not import..." popup
//   * mixed with other files   -> .nki entries removed from the drop, the rest imports as usual
// The .nki paths go to ExtState "Saxmand_NKI_Importer" / "dropQueue" (newline separated),
// and the import script is started unless it is already running (ExtState "busy"); the
// Lua side does the actual Kontakt work.

#include <cctype>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h> // DROPFILES
#else
#include <objc/message.h>
#include <objc/runtime.h>
#endif

#include "sdk/reaper_plugin.h"

static const char *SECTION = "Saxmand_NKI_Importer";
static const char *QUEUE_KEY = "dropQueue";
static const char *VERSION = "0.7";
static const char *SCRIPT_NAME = "Saxmand_NKI Importer - Import dropped files.lua";
#ifdef _WIN32
static const char PATH_SEP = '\\';
#else
static const char PATH_SEP = '/';
#endif

// REAPER API
static void (*ShowConsoleMsg)(const char *msg);
static const char *(*GetExtState)(const char *section, const char *key);
static void (*SetExtState)(const char *section, const char *key, const char *value, bool persist);
static int (*plugin_register)(const char *name, void *infostruct);
static const char *(*GetResourcePath)();
static int (*AddRemoveReaScript)(bool add, int sectionID, const char *scriptfn, bool commit);
static void (*Main_OnCommand)(int command, int flag);
static const char *(*EnumerateFiles)(const char *path, int fileindex);
static const char *(*EnumerateSubdirectories)(const char *path, int subdirindex);

static HWND g_mainHwnd;
static HWND g_arrange;
static WNDPROC g_prevArrangeProc;
static bool g_runPending;

// ---------------------------------------------------------------- platform layer
// initPlatform, setWndProc, callPrevProc, dropFiles, rewriteDrop, DragFinish

#ifdef _WIN32

static bool initPlatform() { return true; }

static WNDPROC setWndProc(HWND hwnd, WNDPROC proc)
{
  return (WNDPROC)SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)proc);
}

static LRESULT callPrevProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
  return CallWindowProcW(g_prevArrangeProc, hwnd, msg, wParam, lParam);
}

static std::string toUtf8(const wchar_t *w)
{
  int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  std::string s(n > 1 ? n - 1 : 0, '\0');
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
  return s;
}

static std::wstring toWide(const std::string &s)
{
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(n > 1 ? n - 1 : 0, L'\0');
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
  return w;
}

// File list of a drop, as UTF-8.
static std::vector<std::string> dropFiles(HDROP drop)
{
  std::vector<std::string> files;
  UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; i++) {
    UINT len = DragQueryFileW(drop, i, nullptr, 0);
    std::wstring buf(len + 1, L'\0');
    if (!DragQueryFileW(drop, i, &buf[0], len + 1)) continue;
    buf.resize(len);
    files.push_back(toUtf8(buf.c_str()));
  }
  return files;
}

// Rewrites the drop's file list in place to only contain `keep` (always shorter than the
// original, so it fits in the same allocation). Windows file lists are UTF-16 (fWide),
// double-null ended. Checks the list really starts with `first`.
static bool rewriteDrop(HDROP drop, const std::string &first, const std::vector<std::string> &keep)
{
  DROPFILES *df = (DROPFILES *)GlobalLock(drop);
  if (!df) return false;
  bool ok = false;
  wchar_t *p = (wchar_t *)((char *)df + df->pFiles);
  if (df->fWide && toUtf8(p) == first) {
    for (const std::string &fn : keep) {
      std::wstring w = toWide(fn);
      memcpy(p, w.c_str(), (w.size() + 1) * sizeof(wchar_t));
      p += w.size() + 1;
    }
    *p = 0;
    ok = true;
  }
  GlobalUnlock(drop);
  return ok;
}

#else // macOS: SWELL

static LONG_PTR (*SWELL_SetWindowLong)(HWND hwnd, int idx, LONG_PTR val);
static HWND (*GetDlgItem)(HWND hwnd, int id);
static UINT (*SWELL_DragQueryFile)(HDROP drop, UINT index, char *buf, UINT bufsz);
static void (*DragFinish)(HDROP drop);
static void *(*GlobalLock)(HANDLE h);

// REAPER provides SWELL through its app delegate (same as WDL's swell-modstub.mm).
static bool initPlatform()
{
  typedef id (*MsgSendClass)(Class, SEL);
  typedef id (*MsgSendId)(id, SEL);
  id app = ((MsgSendClass)objc_msgSend)(objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
  id del = app ? ((MsgSendId)objc_msgSend)(app, sel_registerName("delegate")) : nullptr;
  SEL sel = sel_registerName("swellGetAPPAPIFunc");
  if (!del || !class_respondsToSelector(object_getClass(del), sel)) return false;

  void *(*get)(const char *) = (void *(*)(const char *))((MsgSendId)objc_msgSend)(del, sel);
  if (!get || get(nullptr) != (void *)0x100) return false;

  *(void **)&SWELL_SetWindowLong = get("SetWindowLong");
  *(void **)&GetDlgItem = get("GetDlgItem");
  *(void **)&SWELL_DragQueryFile = get("DragQueryFile");
  *(void **)&DragFinish = get("DragFinish");
  *(void **)&GlobalLock = get("GlobalLock");
  return SWELL_SetWindowLong && GetDlgItem && SWELL_DragQueryFile && DragFinish;
}

static WNDPROC setWndProc(HWND hwnd, WNDPROC proc)
{
  return (WNDPROC)SWELL_SetWindowLong(hwnd, GWL_WNDPROC, (LONG_PTR)proc);
}

static LRESULT callPrevProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
  return g_prevArrangeProc(hwnd, msg, wParam, lParam); // SWELL's CallWindowProc is just this macro
}

// File list of a drop (SWELL lists are UTF-8 already).
static std::vector<std::string> dropFiles(HDROP drop)
{
  std::vector<std::string> files;
  UINT count = SWELL_DragQueryFile(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; i++) {
    char buf[4096];
    if (SWELL_DragQueryFile(drop, i, buf, sizeof(buf))) files.push_back(buf);
  }
  return files;
}

// Rewrites the drop's file list in place to only contain `keep` (always shorter than the
// original, so it fits in the same allocation). SWELL file lists are UTF-8, double-null ended.
// Only relies on pFiles (offset 0), and checks the list really starts with `first`.
static bool rewriteDrop(HDROP drop, const std::string &first, const std::vector<std::string> &keep)
{
  DROPFILES *df = GlobalLock ? (DROPFILES *)GlobalLock(drop) : nullptr;
  if (!df) return false;
  char *p = (char *)df + df->pFiles;
  if (first != p) return false;
  for (const std::string &fn : keep) {
    memcpy(p, fn.c_str(), fn.size() + 1);
    p += fn.size() + 1;
  }
  *p = 0;
  return true;
}

#endif

// ---------------------------------------------------------------- drop handling

static bool isNki(const std::string &fn)
{
  if (fn.size() <= 4) return false;
  std::string ext = fn.substr(fn.size() - 4);
  for (char &c : ext) c = (char)tolower((unsigned char)c);
  return ext == ".nki";
}

static void queueFiles(const std::vector<std::string> &files)
{
  std::string queue = GetExtState(SECTION, QUEUE_KEY);
  for (const std::string &fn : files) {
    if (!queue.empty()) queue += "\n";
    queue += fn;
  }
  SetExtState(SECTION, QUEUE_KEY, queue.c_str(), false);
  if (strcmp(GetExtState(SECTION, "busy"), "1") != 0) g_runPending = true;
}

// Looks for the import script under `dir`, `depth` folder levels deep (ReaPack installs into
// Scripts/<repository>/<category>/). Lists each folder fully before recursing, since REAPER
// caches only one listing at a time.
static std::string findScript(const std::string &dir, int depth)
{
  for (int i = 0; const char *fn = EnumerateFiles(dir.c_str(), i); i++) {
    if (strcmp(fn, SCRIPT_NAME) == 0) return dir + PATH_SEP + fn;
  }
  if (depth == 0) return "";
  std::vector<std::string> subdirs;
  for (int i = 0; const char *sub = EnumerateSubdirectories(dir.c_str(), i); i++) subdirs.push_back(sub);
  for (const std::string &sub : subdirs) {
    std::string found = findScript(dir + PATH_SEP + sub, depth - 1);
    if (!found.empty()) return found;
  }
  return "";
}

// Starts the import script (registering it as an action if needed). Not done from inside
// the drop handler, so REAPER finishes the drop first. Uses the location the scripts store in
// ExtState "importScript" whenever one of them runs, else searches REAPER's Scripts folder.
static void runImportScript()
{
  std::string path = GetExtState(SECTION, "importScript");
  int cmd = path.empty() ? 0 : AddRemoveReaScript(true, 0, path.c_str(), true);
  if (!cmd) {
    path = findScript(std::string(GetResourcePath()) + PATH_SEP + "Scripts", 3);
    if (!path.empty()) cmd = AddRemoveReaScript(true, 0, path.c_str(), true);
    if (cmd) SetExtState(SECTION, "importScript", path.c_str(), true);
  }
  if (cmd) {
    Main_OnCommand(cmd, 0);
    return;
  }
  // drop the queued files, so they don't get imported by surprise on a later drop
  SetExtState(SECTION, QUEUE_KEY, "", false);
  ShowConsoleMsg((std::string("NKI Importer ext: could not find \"") + SCRIPT_NAME +
    "\" in REAPER's Scripts folder - the dropped .nki files were ignored.\n").c_str());
}

static LRESULT CALLBACK arrangeProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
  if (msg == WM_DROPFILES) {
    HDROP drop = (HDROP)wParam;
    std::vector<std::string> all = dropFiles(drop), nki, other;
    for (const std::string &fn : all) (isNki(fn) ? nki : other).push_back(fn);

    if (!nki.empty()) {
      queueFiles(nki);
      if (other.empty()) {
        DragFinish(drop); // what REAPER's own handler would do
        return 0;
      }
      if (!rewriteDrop(drop, all[0], other))
        ShowConsoleMsg("NKI Importer ext: could not remove .nki files from a mixed drop\n");
    }
  }
  return callPrevProc(hwnd, msg, wParam, lParam);
}

// REAPER timer: hooks the arrange view once it exists, and starts the script after a drop.
static void onTimer()
{
  if (!g_arrange) {
    g_arrange = GetDlgItem(g_mainHwnd, 1000);
    if (g_arrange) g_prevArrangeProc = setWndProc(g_arrange, arrangeProc);
  }
  if (g_runPending) {
    g_runPending = false;
    runImportScript();
  }
}

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t *rec)
{
  if (!rec) {
    // unload: restore the arrange view's window proc
    if (plugin_register) plugin_register("-timer", (void *)onTimer);
    if (g_arrange && g_prevArrangeProc) setWndProc(g_arrange, g_prevArrangeProc);
    return 0;
  }
  if (rec->caller_version != REAPER_PLUGIN_VERSION) return 0;

  *(void **)&ShowConsoleMsg = rec->GetFunc("ShowConsoleMsg");
  *(void **)&GetExtState = rec->GetFunc("GetExtState");
  *(void **)&SetExtState = rec->GetFunc("SetExtState");
  *(void **)&GetResourcePath = rec->GetFunc("GetResourcePath");
  *(void **)&AddRemoveReaScript = rec->GetFunc("AddRemoveReaScript");
  *(void **)&Main_OnCommand = rec->GetFunc("Main_OnCommand");
  *(void **)&EnumerateFiles = rec->GetFunc("EnumerateFiles");
  *(void **)&EnumerateSubdirectories = rec->GetFunc("EnumerateSubdirectories");
  if (!ShowConsoleMsg || !GetExtState || !SetExtState || !GetResourcePath || !AddRemoveReaScript || !Main_OnCommand
    || !EnumerateFiles || !EnumerateSubdirectories)
    return 0;

  if (!initPlatform()) {
    ShowConsoleMsg("NKI Importer ext: SWELL functions not available, not loaded\n");
    return 0;
  }

  plugin_register = rec->Register;
  g_mainHwnd = rec->hwnd_main;
  plugin_register("timer", (void *)onTimer);
  SetExtState(SECTION, "extVersion", VERSION, false);
  return 1;
}
