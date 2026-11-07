#ifndef SYLPHY_DESKTOP_LYRICS_WINDOW_H_
#define SYLPHY_DESKTOP_LYRICS_WINDOW_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

// Unowned so minimizing the main window does not hide the lyrics. The runner
// explicitly destroys this window before its Flutter engine is released.
class DesktopLyricsWindow {
 public:
  DesktopLyricsWindow(HWND main_window, flutter::BinaryMessenger* messenger);
  ~DesktopLyricsWindow();

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  bool EnsureWindow();
  bool Render();
  void Hide();
  void Dismiss();
  void SavePosition();
  bool InCloseButton(int x) const;

  HWND main_window_;
  HWND window_ = nullptr;
  ULONG_PTR graphics_token_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::wstring text_;
  DWORD color_ = 0xffe9f0ef;
  double font_size_ = 20;
  bool dragging_ = false;
  POINT drag_start_{};
  RECT drag_frame_{};
};

#endif
