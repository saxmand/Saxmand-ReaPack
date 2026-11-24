#include "vp_fileio.h"

#ifdef _WIN32
  #include <windows.h>
  #include <sys/stat.h>
  #include <wchar.h>

  static std::wstring vpWiden(const std::string& s) {
      if (s.empty()) return std::wstring();
      int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
      std::wstring w(n, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
      return w;
  }

  static std::wstring vpWidenMode(const char* m) {
      std::wstring w;
      for (const char* p = m; p && *p; p++) w += (wchar_t)*p;
      return w;
  }

  FILE* vpFopen(const std::string& path, const char* mode) {
      return _wfopen(vpWiden(path).c_str(), vpWidenMode(mode).c_str());
  }

  bool vpStat(const std::string& path, uint64_t* size, int64_t* mtime) {
      struct _stat64 st;
      if (_wstat64(vpWiden(path).c_str(), &st) != 0) return false;
      if (size)  *size  = (uint64_t)st.st_size;
      if (mtime) *mtime = (int64_t)st.st_mtime;
      return true;
  }

  int vpRemove(const std::string& path) {
      return _wremove(vpWiden(path).c_str());
  }

  int vpRename(const std::string& from, const std::string& to) {
      return _wrename(vpWiden(from).c_str(), vpWiden(to).c_str());
  }

#else
  #include <sys/stat.h>
  #include <unistd.h>

  FILE* vpFopen(const std::string& path, const char* mode) {
      return fopen(path.c_str(), mode);
  }

  bool vpStat(const std::string& path, uint64_t* size, int64_t* mtime) {
      struct stat st;
      if (stat(path.c_str(), &st) != 0) return false;
      if (size)  *size  = (uint64_t)st.st_size;
      if (mtime) *mtime = (int64_t)st.st_mtime;
      return true;
  }

  int vpRemove(const std::string& path) { return remove(path.c_str()); }

  int vpRename(const std::string& from, const std::string& to) {
      return rename(from.c_str(), to.c_str());
  }
#endif
