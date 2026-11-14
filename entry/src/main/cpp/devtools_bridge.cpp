/**
 * 应用内 DevTools 桥：
 * - 回环 TCP 服务器（127.0.0.1:port）
 * - 静态资源：把解压后的 DevTools 前端 dist 以 HTTP 提供给内核加载
 *   （/frontend/<path> 与 /<path> 均映射到 dist 根，兼容相对/绝对两种引用方式）
 * - 透明代理：/json*、/devtools/*、/ 等其余请求原样转发到内核调试后端
 *   抽象命名空间 socket（\0webview_devtools_remote_<pid>），含 WebSocket 升级
 */

#include "napi/native_api.h"
#include "hilog/log.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#define LOG_TAG "ViaDevTools"
#define HILOG_DOMAIN 0x4510
#define HILOG_DEBUG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_DEBUG, HILOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)
#define HILOG_ERROR(fmt, ...) OH_LOG_Print(LOG_APP, LOG_ERROR, HILOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)

static constexpr int MAX_HEAD = 64 * 1024;
static constexpr size_t BACKEND_SOCK_PREFIX = 22; // "webview_devtools_remote_"

static volatile bool g_running = false;
static int g_listenFd = -1;
static int g_port = 0;
static std::string g_frontendDir;
static pthread_t g_acceptThread = 0;

static bool writeAll(int fd, const char *buf, size_t len)
{
    while (len > 0) {
        ssize_t n = write(fd, buf, len);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        buf += n;
        len -= static_cast<size_t>(n);
    }
    return true;
}

static void sendSimpleResponse(int fd, int code, const char *status, const char *body)
{
    size_t bodyLen = strlen(body);
    char head[256];
    int headLen = snprintf(head, sizeof(head),
        "HTTP/1.1 %d %s\r\nContent-Type: text/plain; charset=utf-8\r\n"
        "Content-Length: %zu\r\nConnection: close\r\n\r\n", code, status, bodyLen);
    if (headLen > 0) {
        writeAll(fd, head, static_cast<size_t>(headLen));
        writeAll(fd, body, bodyLen);
    }
}

static const char *mimeOf(const std::string &path)
{
    static const struct {
        const char *ext;
        const char *mime;
    } TABLE[] = {
        {".html", "text/html; charset=utf-8"},
        {".js", "text/javascript; charset=utf-8"},
        {".mjs", "text/javascript; charset=utf-8"},
        {".css", "text/css; charset=utf-8"},
        {".json", "application/json; charset=utf-8"},
        {".svg", "image/svg+xml"},
        {".png", "image/png"},
        {".avif", "image/avif"},
        {".webp", "image/webp"},
        {".gif", "image/gif"},
        {".ico", "image/x-icon"},
        {".wasm", "application/wasm"},
        {".woff2", "font/woff2"},
        {".woff", "font/woff"},
        {".ttf", "font/ttf"},
        {".txt", "text/plain; charset=utf-8"},
    };
    size_t dot = path.rfind('.');
    if (dot == std::string::npos) {
        return "application/octet-stream";
    }
    std::string ext = path.substr(dot);
    for (const auto &entry : TABLE) {
        if (ext == entry.ext) {
            return entry.mime;
        }
    }
    return "application/octet-stream";
}

/** 静态文件服务：path 允许带 /frontend/ 前缀或直接相对 dist 根 */
static void serveStatic(int fd, const std::string &rawPath)
{
    std::string path = rawPath;
    size_t q = path.find('?');
    if (q != std::string::npos) {
        path = path.substr(0, q);
    }
    if (path.rfind("/frontend/", 0) == 0) {
        path = path.substr(sizeof("/frontend") - 1); // 去掉 "/frontend"
    }
    if (!path.empty() && path[0] == '/') {
        path = path.substr(1);
    }
    if (path.empty()) {
        path = "inspector.html";
    }
    if (path.find("..") != std::string::npos) {
        sendSimpleResponse(fd, 403, "Forbidden", "forbidden");
        return;
    }
    std::string full = g_frontendDir + "/" + path;
    int file = open(full.c_str(), O_RDONLY);
    if (file < 0) {
        sendSimpleResponse(fd, 404, "Not Found", "not found");
        return;
    }
    struct stat st;
    if (fstat(file, &st) != 0 || !S_ISREG(st.st_mode)) {
        close(file);
        sendSimpleResponse(fd, 404, "Not Found", "not found");
        return;
    }
    char head[512];
    int headLen = snprintf(head, sizeof(head),
        "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %lld\r\n"
        "Cache-Control: no-cache\r\nConnection: close\r\n\r\n",
        mimeOf(path), static_cast<long long>(st.st_size));
    if (headLen <= 0 || !writeAll(fd, head, static_cast<size_t>(headLen))) {
        close(file);
        return;
    }
    char buf[64 * 1024];
    while (true) {
        ssize_t n = read(file, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (n == 0) {
            break;
        }
        if (!writeAll(fd, buf, static_cast<size_t>(n))) {
            break;
        }
    }
    close(file);
}

/** 诊断：打印某方向首包前 128 字节（截断、去二进制） */
static void logFirst(const char *dir, const char *tag, const char *buf, ssize_t n)
{
    char tmp[129];
    size_t len = static_cast<size_t>(n) < 128 ? static_cast<size_t>(n) : 128;
    memcpy(tmp, buf, len);
    tmp[len] = '\0';
    HILOG_DEBUG("[%{public}s] first %{public}s (%{public}zd bytes): %{public}s", tag, dir, n, tmp);
}

/** 双向透传：任一方读 EOF 时半关闭另一方写方向，两方向均结束才退出 */
static void pump(int a, int b, const char *tag)
{
    struct pollfd fds[2];
    char buf[32 * 1024];
    bool aOpen = true;
    bool bOpen = true;
    bool aLogged = false;
    bool bLogged = false;
    while ((aOpen || bOpen) && g_running) {
        fds[0].fd = a;
        fds[0].events = aOpen ? (POLLIN | POLLHUP) : 0;
        fds[0].revents = 0;
        fds[1].fd = b;
        fds[1].events = bOpen ? (POLLIN | POLLHUP) : 0;
        fds[1].revents = 0;
        int r = poll(fds, 2, 1000);
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (r == 0) {
            continue;
        }
        if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t n = read(a, buf, sizeof(buf));
            if (n <= 0) {
                aOpen = false;
                HILOG_DEBUG("[%{public}s] client side closed (n=%{public}zd errno=%{public}d)",
                    tag, n, errno);
                shutdown(b, SHUT_WR);
            } else {
                if (!aLogged) {
                    aLogged = true;
                    logFirst("client->backend", tag, buf, n);
                }
                if (!writeAll(b, buf, static_cast<size_t>(n))) {
                    break;
                }
            }
        }
        if (fds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            ssize_t n = read(b, buf, sizeof(buf));
            if (n <= 0) {
                bOpen = false;
                HILOG_DEBUG("[%{public}s] backend side closed (n=%{public}zd errno=%{public}d)",
                    tag, n, errno);
                shutdown(a, SHUT_WR);
            } else {
                if (!bLogged) {
                    bLogged = true;
                    logFirst("backend->client", tag, buf, n);
                }
                if (!writeAll(a, buf, static_cast<size_t>(n))) {
                    break;
                }
            }
        }
    }
}

/** 连接内核调试后端抽象 socket；成功返回 fd，失败 -1 */
static int connectBackend()
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return -1;
    }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';
    snprintf(addr.sun_path + 1, sizeof(addr.sun_path) - 1, "webview_devtools_remote_%d", getpid());
    if (connect(fd, reinterpret_cast<struct sockaddr *>(&addr),
        offsetof(struct sockaddr_un, sun_path) + 1 + strlen(addr.sun_path + 1)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/** 请求是否应转发给内核调试后端（与前端 dist 目录名不冲突） */
static bool shouldForward(const std::string &path)
{
    if (path == "/" || path.rfind("/json", 0) == 0 || path.rfind("/devtools/", 0) == 0) {
        return true;
    }
    return false;
}

static void handleClient(int fd)
{
    char head[MAX_HEAD];
    size_t headLen = 0;
    bool headEnd = false;
    while (headLen < sizeof(head) - 1) {
        ssize_t n = read(fd, head + headLen, sizeof(head) - 1 - headLen);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(fd);
            return;
        }
        if (n == 0) {
            break;
        }
        headLen += static_cast<size_t>(n);
        head[headLen] = '\0';
        if (strstr(head, "\r\n\r\n") != nullptr) {
            headEnd = true;
            break;
        }
    }
    if (headLen == 0) {
        close(fd);
        return;
    }
    // 解析请求行：METHOD PATH HTTP/x
    char method[16] = {0};
    char rawPath[2048] = {0};
    if (sscanf(head, "%15s %2047s", method, rawPath) != 2) {
        sendSimpleResponse(fd, 400, "Bad Request", "bad request");
        close(fd);
        return;
    }
    std::string path(rawPath);
    if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
        sendSimpleResponse(fd, 405, "Method Not Allowed", "method not allowed");
        close(fd);
        return;
    }
    if (!shouldForward(path)) {
        serveStatic(fd, path);
        close(fd);
        return;
    }
    // 转发内核调试后端（/json、/devtools/page/* WebSocket 等）
    HILOG_DEBUG("proxy: %{public}s", rawPath);
    int backend = connectBackend();
    if (backend < 0) {
        HILOG_ERROR("backend socket connect failed, path=%{public}s", rawPath);
        sendSimpleResponse(fd, 503, "Service Unavailable",
            "DevTools backend not available (web debug disabled?)");
        close(fd);
        return;
    }
    if (!writeAll(backend, head, headLen)) {
        close(backend);
        close(fd);
        return;
    }
    pump(fd, backend, rawPath);
    close(backend);
    close(fd);
}

struct ClientArg {
    int fd;
};

static void *clientThreadMain(void *raw)
{
    ClientArg *arg = static_cast<ClientArg *>(raw);
    int fd = arg->fd;
    delete arg;
    handleClient(fd);
    return nullptr;
}

static void *acceptThreadMain(void *)
{
    while (g_running) {
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        int client = accept(g_listenFd, reinterpret_cast<struct sockaddr *>(&addr), &len);
        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        // 仅接受回环连接
        if (addr.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) {
            close(client);
            continue;
        }
        ClientArg *arg = new ClientArg{client};
        pthread_t tid;
        if (pthread_create(&tid, nullptr, clientThreadMain, arg) != 0) {
            delete arg;
            close(client);
            continue;
        }
        pthread_detach(tid);
    }
    return nullptr;
}

static napi_value StartBridge(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, nullptr, "startBridge(port: number, frontendDir: string)");
        return nullptr;
    }
    int32_t port = 0;
    napi_get_value_int32(env, args[0], &port);
    char dir[512] = {0};
    size_t dirLen = 0;
    napi_get_value_string_utf8(env, args[1], dir, sizeof(dir) - 1, &dirLen);
    if (g_running) {
        // 已在运行：目录变化时重启
        if (g_port == port && g_frontendDir == std::string(dir)) {
            napi_value result;
            napi_get_boolean(env, true, &result);
            return result;
        }
    }
    if (g_running) {
        g_running = false;
        shutdown(g_listenFd, SHUT_RDWR);
        close(g_listenFd);
        g_listenFd = -1;
        pthread_join(g_acceptThread, nullptr);
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        napi_value result = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(static_cast<uint16_t>(port));
    if (bind(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) != 0 || listen(fd, 16) != 0) {
        HILOG_ERROR("listen failed on 127.0.0.1:%{public}d, errno=%{public}d", port, errno);
        close(fd);
        napi_value result = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }
    g_listenFd = fd;
    g_port = port;
    g_frontendDir = std::string(dir);
    g_running = true;
    if (pthread_create(&g_acceptThread, nullptr, acceptThreadMain, nullptr) != 0) {
        g_running = false;
        close(fd);
        g_listenFd = -1;
        napi_value result = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }
    HILOG_DEBUG("bridge started on 127.0.0.1:%{public}d, dir=%{public}s", port, dir);
    napi_value result = nullptr;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value StopBridge(napi_env env, napi_callback_info)
{
    if (g_running) {
        g_running = false;
        shutdown(g_listenFd, SHUT_RDWR);
        close(g_listenFd);
        g_listenFd = -1;
        pthread_join(g_acceptThread, nullptr);
    }
    napi_value result = nullptr;
    napi_get_boolean(env, true, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"startBridge", nullptr, StartBridge, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopBridge", nullptr, StopBridge, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
