#ifndef SYLPHY_DESKTOP_INTEGRATION_H_
#define SYLPHY_DESKTOP_INTEGRATION_H_
#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Foundation.h>
#include <memory>

class DesktopIntegration {
 public:
  DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopIntegration();
  bool Handle(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  void Send(const char* action);
  HWND window_;
  NOTIFYICONDATAW tray_{};
  bool tray_ready_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
};
#endif
