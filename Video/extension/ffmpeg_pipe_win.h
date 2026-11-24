#pragma once
#ifdef _WIN32

// Running the ffmpeg binary and reading its output, for the platforms that have no
// in-process decoder.
//
// Everything here uses the wide Win32 calls and converts from UTF-8 on the way in.
// REAPER hands paths over as UTF-8, and film projects are full of names that are not
// ASCII -- using the narrow calls would work until the first one and then fail in a way
// that looks like a broken file rather than a broken conversion.

#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

namespace ffp {

inline std::wstring widen(const std::string& s) {
    if (s.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
    return w;
}

inline std::string narrow(const std::wstring& w) {
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr);
    return s;
}

// A quoted argument, for building a command line. Backslashes immediately before the
// closing quote have to be doubled or they escape it -- the rule Windows actually uses,
// which matters because every path here ends in a filename and some end in a backslash.
inline std::wstring quoteArg(const std::wstring& a) {
    std::wstring out = L"\"";
    size_t slashes = 0;
    for (wchar_t c : a) {
        if (c == L'\\') { slashes++; out += c; continue; }
        if (c == L'"') { out.append(slashes + 1, L'\\'); }
        slashes = 0;
        out += c;
    }
    out.append(slashes, L'\\');
    out += L'"';
    return out;
}

// A child process with its stdout (and optionally stderr) on a pipe we read.
class Pipe {
public:
    ~Pipe() { close(); }

    // cmdline must already be quoted. mergeStderr folds stderr into the same pipe,
    // which is what the probe wants since ffmpeg writes its stream summary there.
    bool start(const std::wstring& cmdline, bool mergeStderr) {
        SECURITY_ATTRIBUTES sa{};
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;

        if (!CreatePipe(&rd, &wr, &sa, 1 << 20)) return false;
        // The read end must not reach the child, or the pipe never reports end-of-file:
        // the child would be holding a handle to it and ReadFile would block forever.
        SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);

        // Every slot must hold a valid, inheritable handle once STARTF_USESTDHANDLES is
        // set -- and REAPER is a GUI process with no console, so GetStdHandle returns
        // NULL for stdin and stderr. Passing those straight through made CreateProcessW
        // fail outright, which surfaced as "could not run ffmpeg" no matter how correct
        // the path was. So the slots we are not piping get NUL, the Windows equivalent
        // of /dev/null, opened inheritable.
        nul = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                          OPEN_EXISTING, 0, nullptr);
        if (nul == INVALID_HANDLE_VALUE) nul = nullptr;

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdOutput = wr;
        si.hStdError  = mergeStderr ? wr : nul;
        si.hStdInput  = nul;

        std::vector<wchar_t> mutableCmd(cmdline.begin(), cmdline.end());
        mutableCmd.push_back(L'\0');

        PROCESS_INFORMATION pi{};
        BOOL ok = CreateProcessW(nullptr, mutableCmd.data(), nullptr, nullptr, TRUE,
                                 CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
        lastError = ok ? 0 : (int)GetLastError();
        // Our copy of the write end goes immediately: while we hold one, the pipe
        // cannot signal end-of-file when the child exits.
        CloseHandle(wr); wr = nullptr;
        if (nul) { CloseHandle(nul); nul = nullptr; }
        if (!ok) { CloseHandle(rd); rd = nullptr; return false; }

        CloseHandle(pi.hThread);
        proc = pi.hProcess;
        return true;
    }

    // Fills buf with exactly n bytes unless the stream ends first. Returns how many
    // were read; a short read means end of stream.
    int readExact(void* buf, int n) {
        char* p = (char*)buf;
        int got = 0;
        while (got < n) {
            DWORD r = 0;
            if (!ReadFile(rd, p + got, (DWORD)(n - got), &r, nullptr) || r == 0) break;
            got += (int)r;
        }
        return got;
    }

    // Everything until the stream ends. For the probe, whose output is small.
    std::string readAll(size_t cap = 1 << 20) {
        std::string out;
        char buf[8192];
        for (;;) {
            DWORD r = 0;
            if (!ReadFile(rd, buf, sizeof(buf), &r, nullptr) || r == 0) break;
            out.append(buf, r);
            if (out.size() >= cap) break;
        }
        return out;
    }

    // Waits for the child to finish. True if it exited within the timeout.
    //
    // Needed as well as reading the pipe, because the two are not the same event: the
    // pipe reports end-of-file when the child closes its stdout, which happens as it
    // exits but before it has finished. Anything that depends on what the child wrote
    // to a FILE -- rather than to the pipe -- has to wait for the process itself.
    bool waitExit(DWORD ms) {
        if (!proc) return true;
        return WaitForSingleObject(proc, ms) == WAIT_OBJECT_0;
    }

    void close() {
        if (rd) { CloseHandle(rd); rd = nullptr; }
        if (wr) { CloseHandle(wr); wr = nullptr; }
        if (proc) {
            // Reading may stop early -- a cancelled analysis, or a caller that has seen
            // enough -- and ffmpeg would then sit blocked on a full pipe forever. So
            // give it a moment to leave on its own and only then insist.
            //
            // The moment matters. This used to be WaitForSingleObject(proc, 0), which
            // asks "have you exited already?" and almost always says no, because the
            // pipe signals end-of-file while the child is still shutting down. It then
            // terminated ffmpeg mid-exit -- harmless when we had already read what we
            // wanted off the pipe, and fatal when ffmpeg was writing a frame to a file,
            // because the file was killed before it was flushed. That is why cut
            // detection worked and previews came back blank.
            if (WaitForSingleObject(proc, 5000) == WAIT_TIMEOUT) TerminateProcess(proc, 0);
            WaitForSingleObject(proc, 2000);
            CloseHandle(proc);
            proc = nullptr;
        }
    }

    // 0 when the process started, otherwise GetLastError from CreateProcessW. 2 is
    // "file not found", which for this call means the ffmpeg executable, not the video.
    int lastError = 0;

private:
    HANDLE rd = nullptr, wr = nullptr, proc = nullptr, nul = nullptr;
};

// A failure to start, in words. 2 and 3 are the ones that actually happen, and they say
// something quite specific: the path is wrong, rather than ffmpeg being unhappy.
inline std::string startFailure(const std::string& exe, int err) {
    char buf[512];
    const char* why =
        (err == 2)   ? "no such file" :
        (err == 3)   ? "no such folder" :
        (err == 5)   ? "access denied" :
        (err == 193) ? "not a valid 64-bit executable" : "could not be started";
    snprintf(buf, sizeof(buf),
             "ffmpeg %s (error %d): %s\n"
             "Windows decodes through ffmpeg, so set its path on the Settings page.",
             why, err, exe.empty() ? "(no path set, looked for \"ffmpeg\" on PATH)" : exe.c_str());
    return buf;
}

// Duration, frame rate and size, from the summary ffmpeg prints for its input.
//
// Parsed from that text because it is what every ffmpeg build prints and needs no
// second tool: ffprobe is a separate executable and is not always installed beside
// ffmpeg. The two lines read are "Duration: HH:MM:SS.ss" and the video stream line,
// which carries "<n> fps" and "<w>x<h>".
struct Probe {
    double duration = 0.0;
    double fps      = 0.0;
    int    width    = 0;
    int    height   = 0;
    bool   hasVideo = false;
    bool   hasAudio = false;
};

inline bool probe(const std::string& exe, const std::string& path, Probe* out, std::string* err) {
    std::wstring cmd = quoteArg(widen(exe)) + L" -hide_banner -i " + quoteArg(widen(path));
    Pipe p;
    if (!p.start(cmd, /*mergeStderr=*/true)) {
        if (err) *err = startFailure(exe, p.lastError);
        return false;
    }
    std::string text = p.readAll();
    p.close();

    // "  Duration: 00:01:23.45, start: ..."
    size_t d = text.find("Duration:");
    if (d != std::string::npos) {
        int hh = 0, mm = 0; double ss = 0;
        if (sscanf(text.c_str() + d, "Duration: %d:%d:%lf", &hh, &mm, &ss) == 3)
            out->duration = hh * 3600.0 + mm * 60.0 + ss;
    }

    // the video stream line, e.g. "Stream #0:0(und): Video: h264 ..., 1920x1080 ..., 25 fps,"
    size_t v = text.find(": Video:");
    if (v != std::string::npos) {
        out->hasVideo = true;
        size_t lineEnd = text.find('\n', v);
        std::string line = text.substr(v, (lineEnd == std::string::npos ? text.size() : lineEnd) - v);

        size_t f = line.find(" fps");
        if (f != std::string::npos) {
            // walk back over the number
            size_t b = f;
            while (b > 0 && (isdigit((unsigned char)line[b-1]) || line[b-1] == '.')) b--;
            out->fps = atof(line.c_str() + b);
        }
        // the first WxH on the line that is not part of something else
        for (size_t i = 1; i + 1 < line.size(); i++) {
            if (line[i] == 'x' && isdigit((unsigned char)line[i-1]) && isdigit((unsigned char)line[i+1])) {
                size_t b = i;
                while (b > 0 && isdigit((unsigned char)line[b-1])) b--;
                int w = atoi(line.c_str() + b), h = atoi(line.c_str() + i + 1);
                if (w >= 16 && h >= 16) { out->width = w; out->height = h; break; }
            }
        }
    }
    if (text.find(": Audio:") != std::string::npos) out->hasAudio = true;

    if (!out->hasVideo && !out->hasAudio) {
        if (err) *err = "ffmpeg found no video or audio stream in this file";
        return false;
    }
    return true;
}

} // namespace ffp
#endif // _WIN32
