// SPDX-License-Identifier: MIT
// Local controller forwarding for Sunshine's macOS backend, no virtual HID driver.
#pragma once
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <pwd.h>
#include <string>
#include <thread>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>

namespace vgf {
class Input {
  struct Pad { bool active = false; unsigned buttons = 0; int lt=0, rt=0, lx=0, ly=0, rx=0, ry=0;
    std::chrono::steady_clock::time_point seen = std::chrono::steady_clock::now(); };
  std::array<Pad,16> pads{};
  std::mutex mutex;
  std::condition_variable wake;
  bool ending = false;
  int fd = -1;
  sockaddr_un address{};
  std::thread heartbeat;
  void send(int id) {
    if (fd < 0) return;
    const auto &p = pads[id];
    char data[512];
    int n = std::snprintf(data, sizeof(data),
      "{\"version\":1,\"id\":%d,\"active\":%s,\"buttons\":%u,\"lt\":%d,\"rt\":%d,\"lx\":%d,\"ly\":%d,\"rx\":%d,\"ry\":%d}",
      id, p.active ? "true":"false", p.buttons, p.lt,p.rt,p.lx,p.ly,p.rx,p.ry);
    if (n > 0 && n < static_cast<int>(sizeof(data)))
      ::sendto(fd, data, n, 0, reinterpret_cast<sockaddr*>(&address), sizeof(address));
  }
 public:
  static std::string defaultPath() {
    auto *pw = getpwuid(getuid());
    return pw ? std::string(pw->pw_dir) + "/Library/Application Support/VideoGameFilter/moonlight.sock" : "";
  }
  explicit Input(const std::string &path = defaultPath()) {
    if (path.empty()) return;
    if (path.size() >= sizeof(address.sun_path)) return;
    address.sun_family = AF_UNIX; address.sun_len = sizeof(address);
    std::memcpy(address.sun_path, path.c_str(), path.size()+1);
    fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) return;
    fcntl(fd, F_SETFL, O_NONBLOCK); fcntl(fd, F_SETFD, FD_CLOEXEC);
    heartbeat = std::thread([this] {
      std::unique_lock<std::mutex> guard(mutex);
      while (!wake.wait_for(guard, std::chrono::milliseconds(100), [this]{return ending;}))
        for (int i=0; i<16; ++i) if (pads[i].active) {
          auto &p = pads[i];
          if (std::chrono::steady_clock::now() - p.seen > std::chrono::milliseconds(350)) {
            p.buttons=0; p.lt=p.rt=p.lx=p.ly=p.rx=p.ry=0;
          }
          send(i);
        }
    });
  }
  ~Input() {
    { std::lock_guard<std::mutex> guard(mutex); ending = true;
      for (int i=0; i<16; ++i) if (pads[i].active) { pads[i].active=false; send(i); }
    }
    wake.notify_all(); if (heartbeat.joinable()) heartbeat.join(); if (fd>=0) close(fd);
  }
  bool allocate(int id) {
    if (id<0 || id>=16 || fd<0) return false;
    std::lock_guard<std::mutex> guard(mutex); pads[id] = {}; pads[id].active=true; send(id); return true;
  }
  void alive(int id) {
    if (id<0 || id>=16) return;
    std::lock_guard<std::mutex> guard(mutex);
    if (pads[id].active) pads[id].seen=std::chrono::steady_clock::now();
  }
  void release(int id) {
    if (id<0 || id>=16) return;
    std::lock_guard<std::mutex> guard(mutex); pads[id] = {}; send(id);
  }
  void update(int id, unsigned buttons, int lt, int rt, int lx, int ly, int rx, int ry) {
    if (id<0 || id>=16) return;
    std::lock_guard<std::mutex> guard(mutex);
    if (!pads[id].active) return;
    pads[id] = {true,buttons,lt,rt,lx,ly,rx,ry}; send(id);
  }
};
inline Input &input() { static Input value; return value; }
}
