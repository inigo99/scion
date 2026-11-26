/* http.cpp — HTTP(S) requests for URLSession (HC_net's NET_HTTP_*), on the host's own HTTP stack: WinHTTP on Windows,
 * libcurl on Linux. It follows redirects, speaks TLS with the host's trusted certificates, uses the host's proxy
 * settings and decompresses gzip and deflate bodies. A request is made (NEW), sent until the final response's headers
 * are in (SEND), and its body read in pieces (READ); CANCEL, from another thread, makes a blocked SEND or READ return.
 * Errors are NSURLErrorDomain codes, which the guest's Foundation turns into NSErrors. */
#include "scion.h"
#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#include <shlwapi.h>
#else
#include <curl/curl.h>
#endif
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

static inline A G(A x) { return g_guest_arm ? (A)arm64_translate((uint64_t)x) : x; }
template<typename T> static T *GP(A x) { return x ? (T *)G(x) : nullptr; }

enum {   /* NSURLErrorDomain */
    E_UNKNOWN = -1, E_CANCELLED = -999, E_BAD_URL = -1000, E_TIMED_OUT = -1001, E_UNSUPPORTED_URL = -1002,
    E_NO_HOST = -1003, E_NO_CONNECT = -1004, E_LOST = -1005, E_REDIRECTS = -1007, E_TLS = -1200, E_UNTRUSTED = -1202,
};

struct Http : std::enable_shared_from_this<Http> {
    std::string method, url, headers, body;
    int64_t timeout_ms = 60000;
    std::atomic<bool> cancelled{false};
    std::string got, resp_headers;   /* body received and not read yet (from `off`), the final response's headers */
    size_t off = 0;
    bool headers_done = false, done = false;
#ifdef _WIN32
    std::mutex m;                    /* the fields below and above, between the worker and SEND / READ / CANCEL */
    std::condition_variable cv;
    HINTERNET conn = nullptr, req = nullptr;
    std::wstring final_url;          /* the URL, as redirects change it */
    int32_t status = 0;
    A error = 0;
#else
    CURL *easy = nullptr;
    CURLM *multi = nullptr;
    curl_slist *list = nullptr;
    CURLcode result = CURLE_OK;
#endif
    ~Http();
};

static std::mutex g_m;
static std::map<int64_t, std::shared_ptr<Http>> g_http;
static int64_t g_next = 1;
static std::shared_ptr<Http> get(A h) {
    std::lock_guard<std::mutex> l(g_m);
    auto it = g_http.find((int64_t)h);
    return it == g_http.end() ? nullptr : it->second;
}

/* the response's headers and URL into the guest's buffers (cut to fit) */
static void put(const std::string &s, A buf, A cap) {
    char *p = GP<char>(buf);
    if (!p || !cap) return;
    size_t n = std::min<size_t>(s.size(), (size_t)cap - 1);
    memcpy(p, s.data(), n);
    p[n] = 0;
}

#ifdef _WIN32
/* ======================================================================= Windows: WinHTTP. Its synchronous calls run
 * in a worker thread per request, which SEND and READ wait for: CANCEL can then make them return at once (Wine's
 * WinHTTP does not abort a blocked call when its handle is closed). */
static std::wstring wide(const std::string &s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
    return w;
}
static std::string narrow(const wchar_t *w, size_t n) {
    int k = WideCharToMultiByte(CP_UTF8, 0, w, (int)n, nullptr, 0, nullptr, nullptr);
    std::string s(k, 0);
    WideCharToMultiByte(CP_UTF8, 0, w, (int)n, &s[0], k, nullptr, nullptr);
    return s;
}
static HINTERNET session() {
    static HINTERNET s = [] {
        /* the system's proxy settings (automatic proxy needs Windows 8.1) */
        HINTERNET h = WinHttpOpen(L"Scion", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!h) h = WinHttpOpen(L"Scion", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        return h;
    }();
    return s;
}
Http::~Http() {
    if (req) WinHttpCloseHandle(req);
    if (conn) WinHttpCloseHandle(conn);
}
static A fail(Http *h) {
    DWORD e = GetLastError();
    if (h->cancelled) return E_CANCELLED;
    switch (e) {
    case ERROR_WINHTTP_TIMEOUT: return E_TIMED_OUT;
    case ERROR_WINHTTP_NAME_NOT_RESOLVED: return E_NO_HOST;
    case ERROR_WINHTTP_CANNOT_CONNECT: return E_NO_CONNECT;
    case ERROR_WINHTTP_CONNECTION_ERROR: case ERROR_WINHTTP_INVALID_SERVER_RESPONSE: return E_LOST;
    case ERROR_WINHTTP_OPERATION_CANCELLED: return E_CANCELLED;
    case ERROR_WINHTTP_INVALID_URL: return E_BAD_URL;
    case ERROR_WINHTTP_UNRECOGNIZED_SCHEME: return E_UNSUPPORTED_URL;
    case ERROR_WINHTTP_REDIRECT_FAILED: return E_REDIRECTS;
    case ERROR_WINHTTP_SECURE_CERT_DATE_INVALID: case ERROR_WINHTTP_SECURE_CERT_CN_INVALID:
    case ERROR_WINHTTP_SECURE_INVALID_CA: case ERROR_WINHTTP_SECURE_CERT_REVOKED: case ERROR_WINHTTP_SECURE_INVALID_CERT:
    case ERROR_WINHTTP_SECURE_CERT_WRONG_USAGE: return E_UNTRUSTED;
    case ERROR_WINHTTP_SECURE_FAILURE: case ERROR_WINHTTP_SECURE_CHANNEL_ERROR: return E_TLS;
    }
    return E_UNKNOWN;
}
/* a redirect's Location (absolute or relative: Wine passes it as sent) against the URL it came from. The URL is taken
 * from these rather than WINHTTP_OPTION_URL, which Wine leaves at the first one. */
static void CALLBACK on_status(HINTERNET, DWORD_PTR ctx, DWORD status, void *info, DWORD) {
    if (status != WINHTTP_CALLBACK_STATUS_REDIRECT || !ctx || !info) return;
    Http *h = (Http *)ctx;
    static thread_local wchar_t out[8192];
    DWORD n = 8192;
    if (UrlCombineW(h->final_url.c_str(), (const wchar_t *)info, out, &n, 0) == S_OK) h->final_url = out;
}

/* the request's timeout is also kept here, as the time without news from the worker (Wine's WinHTTP lets a
 * receive wait longer); h->m is held */
static A timed_out(Http *h) {
    h->cancelled = true;
    if (h->req) { WinHttpCloseHandle(h->req); h->req = nullptr; }
    h->cv.notify_all();
    return E_TIMED_OUT;
}

/* sends the request, then reads the body ahead of READ (up to 4 MB) */
static void work(std::shared_ptr<Http> h, HINTERNET r) {
    A err = 0;
    std::wstring hdr = wide(h->headers);
    if (!WinHttpSendRequest(r, hdr.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : hdr.c_str(), (DWORD)-1L,
                            h->body.empty() ? WINHTTP_NO_REQUEST_DATA : (void *)h->body.data(), (DWORD)h->body.size(),
                            (DWORD)h->body.size(), (DWORD_PTR)h.get())
        || !WinHttpReceiveResponse(r, nullptr))
        err = fail(h.get());
    else {
        DWORD status = 0, n = sizeof status;
        WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &status, &n, WINHTTP_NO_HEADER_INDEX);
        n = 0;
        WinHttpQueryHeaders(r, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, WINHTTP_NO_OUTPUT_BUFFER, &n, WINHTTP_NO_HEADER_INDEX);
        std::wstring raw(n / sizeof(wchar_t), 0);
        std::string headers;
        if (n && WinHttpQueryHeaders(r, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, &raw[0], &n, WINHTTP_NO_HEADER_INDEX)) {
            std::string s = narrow(raw.c_str(), wcsnlen(raw.c_str(), raw.size()));
            size_t eol = s.find("\r\n");   /* the status line goes */
            if (eol != std::string::npos) headers = s.substr(eol + 2);
        }
        {
            std::lock_guard<std::mutex> l(h->m);
            h->status = (int32_t)status;
            h->resp_headers = headers;
            h->headers_done = true;
        }
        h->cv.notify_all();
        std::vector<char> buf(1 << 16);
        for (;;) {
            {
                std::unique_lock<std::mutex> l(h->m);
                h->cv.wait(l, [&] { return h->got.size() - h->off < (4u << 20) || h->cancelled; });
                if (h->cancelled) break;
            }
            DWORD got = 0;
            if (!WinHttpReadData(r, buf.data(), (DWORD)buf.size(), &got)) { err = fail(h.get()); break; }
            if (!got) break;
            std::lock_guard<std::mutex> l(h->m);
            h->got.append(buf.data(), got);
            h->cv.notify_all();
        }
    }
    std::lock_guard<std::mutex> l(h->m);
    h->error = err;
    h->done = true;
    h->cv.notify_all();
}

static A http_send(Http *h, dhttpreq *q) {
    std::wstring url = wide(h->url);
    h->final_url = url;
    URL_COMPONENTS u{};
    u.dwStructSize = sizeof u;
    u.dwSchemeLength = u.dwHostNameLength = u.dwUrlPathLength = u.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(url.c_str(), (DWORD)url.size(), 0, &u)) return E_BAD_URL;
    if (u.nScheme != INTERNET_SCHEME_HTTP && u.nScheme != INTERNET_SCHEME_HTTPS) return E_UNSUPPORTED_URL;
    std::wstring host(u.lpszHostName, u.dwHostNameLength), path(u.lpszUrlPath, u.dwUrlPathLength);
    path.append(u.lpszExtraInfo, u.dwExtraInfoLength);
    if (path.empty()) path = L"/";
    {
        std::lock_guard<std::mutex> l(h->m);
        if (h->cancelled) return E_CANCELLED;
        h->conn = WinHttpConnect(session(), host.c_str(), u.nPort, 0);
        if (h->conn)
            h->req = WinHttpOpenRequest(h->conn, wide(h->method).c_str(), path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                        WINHTTP_DEFAULT_ACCEPT_TYPES, u.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
        if (!h->req) return fail(h);
    }
    HINTERNET r = h->req;
    WinHttpSetStatusCallback(r, on_status, WINHTTP_CALLBACK_FLAG_REDIRECT, 0);
    int t = (int)std::min<int64_t>(h->timeout_ms, 0x7fffffff);
    WinHttpSetTimeouts(r, t, t, t, t);
    DWORD dec = WINHTTP_DECOMPRESSION_FLAG_ALL;   /* Windows 8.1 and newer; without it bodies come as sent */
    WinHttpSetOption(r, WINHTTP_OPTION_DECOMPRESSION, &dec, sizeof dec);
    std::thread(work, h->shared_from_this(), r).detach();
    std::unique_lock<std::mutex> l(h->m);
    if (!h->cv.wait_for(l, std::chrono::milliseconds(h->timeout_ms), [h] { return h->headers_done || h->done || h->cancelled; }))
        return timed_out(h);
    if (h->cancelled) return E_CANCELLED;
    if (!h->headers_done) return h->error;
    q->status = h->status;
    put(h->resp_headers, q->resp_headers, q->resp_headers_cap);
    put(narrow(h->final_url.c_str(), h->final_url.size()), q->final_url, q->final_url_cap);
    return 0;
}

static A http_read(Http *h, void *buf, A n) {
    std::unique_lock<std::mutex> l(h->m);
    if (!h->cv.wait_for(l, std::chrono::milliseconds(h->timeout_ms), [h] { return h->off < h->got.size() || h->done || h->cancelled; }))
        return timed_out(h);
    if (h->cancelled) return E_CANCELLED;
    if (h->off < h->got.size()) {
        size_t k = std::min<size_t>((size_t)n, h->got.size() - h->off);
        memcpy(buf, h->got.data() + h->off, k);
        h->off += k;
        if (h->off == h->got.size()) { h->got.clear(); h->off = 0; h->cv.notify_all(); }
        return (A)k;
    }
    return h->error;
}

static void http_cancel(Http *h) {
    std::lock_guard<std::mutex> l(h->m);
    h->cancelled = true;
    if (h->req) { WinHttpCloseHandle(h->req); h->req = nullptr; }   /* (on Windows this aborts a blocked call) */
    h->cv.notify_all();
}
#else
/* ======================================================================= Linux: libcurl (a multi handle per request,
 * driven by SEND and READ until they have what they wait for) */
Http::~Http() {
    if (multi && easy) curl_multi_remove_handle(multi, easy);
    if (easy) curl_easy_cleanup(easy);
    if (multi) curl_multi_cleanup(multi);
    curl_slist_free_all(list);
}
static size_t on_body(char *p, size_t s, size_t n, void *u) {
    ((Http *)u)->got.append(p, s * n);
    return s * n;
}
static size_t on_header(char *p, size_t s, size_t n, void *u) {
    Http *h = (Http *)u;
    std::string line(p, s * n);
    if (line.compare(0, 5, "HTTP/") == 0) {   /* another response (after a redirect or a 100 Continue) */
        h->resp_headers.clear();
    } else if (line == "\r\n" || line == "\n") {
        long code = 0;
        curl_easy_getinfo(h->easy, CURLINFO_RESPONSE_CODE, &code);
        std::string lower = h->resp_headers;
        for (char &c : lower) c = (char)tolower((unsigned char)c);
        bool redirect = code >= 300 && code < 400 && code != 304 && (lower.find("\nlocation:") != std::string::npos || lower.compare(0, 9, "location:") == 0);
        if (code >= 200 && !redirect) h->headers_done = true;   /* the final response's */
    } else {
        while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
        h->resp_headers += line + "\r\n";
    }
    return s * n;
}
static int on_progress(void *u, curl_off_t, curl_off_t, curl_off_t, curl_off_t) { return ((Http *)u)->cancelled ? 1 : 0; }

static A error_of(CURLcode c) {
    switch (c) {
    case CURLE_COULDNT_RESOLVE_HOST: case CURLE_COULDNT_RESOLVE_PROXY: return E_NO_HOST;
    case CURLE_COULDNT_CONNECT: return E_NO_CONNECT;
    case CURLE_OPERATION_TIMEDOUT: return E_TIMED_OUT;
    case CURLE_ABORTED_BY_CALLBACK: return E_CANCELLED;
    case CURLE_TOO_MANY_REDIRECTS: return E_REDIRECTS;
    case CURLE_URL_MALFORMAT: return E_BAD_URL;
    case CURLE_UNSUPPORTED_PROTOCOL: return E_UNSUPPORTED_URL;
    case CURLE_PEER_FAILED_VERIFICATION: case CURLE_SSL_CACERT_BADFILE: case CURLE_SSL_ISSUER_ERROR: return E_UNTRUSTED;
    case CURLE_SSL_CONNECT_ERROR: case CURLE_SSL_CERTPROBLEM: case CURLE_SSL_CIPHER: return E_TLS;
    case CURLE_GOT_NOTHING: case CURLE_RECV_ERROR: case CURLE_SEND_ERROR: case CURLE_PARTIAL_FILE: return E_LOST;
    default: return E_UNKNOWN;
    }
}

/* runs the transfer until `ready` (or its end) */
template<typename F> static void pump(Http *h, F ready) {
    while (!ready() && !h->done) {
        int running = 0;
        curl_multi_perform(h->multi, &running);
        int left;
        while (CURLMsg *m = curl_multi_info_read(h->multi, &left))
            if (m->msg == CURLMSG_DONE) { h->done = true; h->result = m->data.result; }
        if (!running) h->done = true;
        if (ready() || h->done) break;
        curl_multi_poll(h->multi, nullptr, 0, 100, nullptr);   /* (wakes up to see CANCEL) */
    }
}

static A http_send(Http *h, dhttpreq *q) {
    static std::once_flag once;
    std::call_once(once, [] { curl_global_init(CURL_GLOBAL_DEFAULT); });
    if (h->cancelled) return E_CANCELLED;
    CURL *c = h->easy = curl_easy_init();
    h->multi = curl_multi_init();
    if (!c || !h->multi) return E_UNKNOWN;
    curl_easy_setopt(c, CURLOPT_URL, h->url.c_str());
    curl_easy_setopt(c, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(c, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_MAXREDIRS, 16L);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");   /* every encoding libcurl decodes */
    curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);
    long secs = (long)std::max<int64_t>(1, (h->timeout_ms + 999) / 1000);
    curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, secs);
    curl_easy_setopt(c, CURLOPT_LOW_SPEED_LIMIT, 1L);   /* the timeout is for a request that stops moving */
    curl_easy_setopt(c, CURLOPT_LOW_SPEED_TIME, secs);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, h);
    curl_easy_setopt(c, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(c, CURLOPT_HEADERDATA, h);
    curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(c, CURLOPT_XFERINFOFUNCTION, on_progress);
    curl_easy_setopt(c, CURLOPT_XFERINFODATA, h);
    if (h->method == "HEAD") curl_easy_setopt(c, CURLOPT_NOBODY, 1L);
    else if (h->method != "GET" || !h->body.empty()) curl_easy_setopt(c, CURLOPT_CUSTOMREQUEST, h->method.c_str());
    if (!h->body.empty() || h->method == "POST" || h->method == "PUT" || h->method == "PATCH") {
        curl_easy_setopt(c, CURLOPT_POSTFIELDS, h->body.data());
        curl_easy_setopt(c, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)h->body.size());
    }
    size_t at = 0;
    while (at < h->headers.size()) {
        size_t eol = h->headers.find("\r\n", at);
        if (eol == std::string::npos) eol = h->headers.size();
        if (eol > at) h->list = curl_slist_append(h->list, h->headers.substr(at, eol - at).c_str());
        at = eol + 2;
    }
    h->list = curl_slist_append(h->list, "Expect:");   /* no 100-continue round trip */
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, h->list);
    curl_multi_add_handle(h->multi, c);
    pump(h, [h] { return h->headers_done; });
    if (!h->headers_done) return h->cancelled ? E_CANCELLED : h->result != CURLE_OK ? error_of(h->result) : E_LOST;
    long code = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
    q->status = (int32_t)code;
    char *url = nullptr;
    curl_easy_getinfo(c, CURLINFO_EFFECTIVE_URL, &url);
    put(url ? url : h->url, q->final_url, q->final_url_cap);
    put(h->resp_headers, q->resp_headers, q->resp_headers_cap);
    return 0;
}

static A http_read(Http *h, void *buf, A n) {
    if (!h->multi) return E_UNKNOWN;
    pump(h, [h] { return h->off < h->got.size() || h->cancelled; });
    if (h->cancelled) return E_CANCELLED;
    if (h->off < h->got.size()) {
        size_t k = std::min<size_t>((size_t)n, h->got.size() - h->off);
        memcpy(buf, h->got.data() + h->off, k);
        h->off += k;
        if (h->off == h->got.size()) { h->got.clear(); h->off = 0; }
        return (A)k;
    }
    return h->result == CURLE_OK ? 0 : error_of(h->result);
}

static void http_cancel(Http *h) { h->cancelled = true; }
#endif

/* ======================================================================= NET_HTTP_* */
A http_op(A op, A a, A b, A c) {
    switch (op) {
    case NET_HTTP_NEW: {
        dhttpreq *q = GP<dhttpreq>(a);
        if (!q || !q->url) return E_BAD_URL;
        auto h = std::make_shared<Http>();
        h->method = q->method ? GP<char>(q->method) : "GET";
        h->url = GP<char>(q->url);
        if (q->headers) h->headers = GP<char>(q->headers);
        if (q->body && q->body_len) h->body.assign(GP<char>(q->body), (size_t)q->body_len);
        if (q->timeout_ms > 0) h->timeout_ms = q->timeout_ms;
        std::lock_guard<std::mutex> l(g_m);
        g_http[g_next] = h;
        return g_next++;
    }
    case NET_HTTP_SEND: {
        auto h = get(a);
        dhttpreq *q = GP<dhttpreq>(b);
        return h && q ? http_send(h.get(), q) : E_UNKNOWN;
    }
    case NET_HTTP_READ: {
        auto h = get(a);
        return h && b ? http_read(h.get(), GP<void>(b), c) : E_UNKNOWN;
    }
    case NET_HTTP_CANCEL:
        if (auto h = get(a)) http_cancel(h.get());
        return 0;
    case NET_HTTP_CLOSE: {
        if (auto h = get(a)) http_cancel(h.get());   /* (stops a request whose body is not all read) */
        std::lock_guard<std::mutex> l(g_m);
        g_http.erase((int64_t)a);   /* (freed when the last call using it returns) */
        return 0;
    }
    }
    return E_UNKNOWN;
}
