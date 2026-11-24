/* launcher.cpp — scionw.exe: runs `scion.exe <args>` without a console window (what the Start menu shortcuts of
 * installed apps start). The program's output goes to %LOCALAPPDATA%\scion\logs\<App>.log. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <string>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    wchar_t self[MAX_PATH * 2]; GetModuleFileNameW(nullptr, self, MAX_PATH * 2);
    std::wstring dir = self; dir = dir.substr(0, dir.find_last_of(L'\\'));
    /* the command line after our own program name, passed on as it is */
    const wchar_t *cl = GetCommandLineW();
    if (*cl == L'"') { cl++; while (*cl && *cl != L'"') cl++; if (*cl) cl++; } else while (*cl && *cl != L' ') cl++;
    std::wstring cmd = L"\"" + dir + L"\\scion.exe\"" + cl;
    /* log named after the app: the first argument's last path component */
    int argc; wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::wstring name = argc > 1 ? argv[1] : L"scion";
    while (!name.empty() && (name.back() == L'\\' || name.back() == L'/')) name.pop_back();
    name = name.substr(name.find_last_of(L"\\/") + 1);
    LocalFree(argv);
    wchar_t *la = nullptr; std::wstring logs;
    if (SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &la) == S_OK) logs = la;
    CoTaskMemFree(la);
    logs += L"\\scion"; CreateDirectoryW(logs.c_str(), nullptr);
    logs += L"\\logs"; CreateDirectoryW(logs.c_str(), nullptr);
    SECURITY_ATTRIBUTES sa{sizeof sa, nullptr, TRUE};
    HANDLE log = CreateFileW((logs + L"\\" + name + L".log").c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_ALWAYS, 0, nullptr);
    STARTUPINFOW si{sizeof si}; PROCESS_INFORMATION pi;
    if (log != INVALID_HANDLE_VALUE) { si.dwFlags = STARTF_USESTDHANDLES; si.hStdOutput = si.hStdError = log; si.hStdInput = nullptr; }
    if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        MessageBoxW(nullptr, (L"Could not start " + cmd).c_str(), L"scion", MB_ICONERROR);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD rc = 0; GetExitCodeProcess(pi.hProcess, &rc);
    return (int)rc;
}
