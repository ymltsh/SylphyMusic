#include "desktop_lyrics_window.h"

#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace {
constexpr UINT_PTR kIdleTimer = 1;
constexpr UINT_PTR kFadeTimer = 2;
constexpr UINT kControlsIdleMs = 2500;
constexpr ULONGLONG kControlsFadeMs = 350;

constexpr wchar_t kWindowClass[] = L"SylphyMusicDesktopLyrics";
constexpr wchar_t kSettingsKey[] = L"Software\\SylphyMusic\\DesktopLyrics";

const flutter::EncodableValue* Value(const flutter::EncodableMap& values,
                                     const char* key) {
  auto it = values.find(flutter::EncodableValue(key));
  return it == values.end() ? nullptr : &it->second;
}

std::wstring WideText(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        text.data(), static_cast<int>(text.size()),
                                        nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                      static_cast<int>(text.size()), result.data(), length);
  return result;
}

RECT WorkArea(HWND window) {
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) {
    return monitor.rcWork;
  }
  RECT work{};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  return work;
}

float Scale(HWND window) {
  const UINT dpi = GetDpiForWindow(window);
  return static_cast<float>(dpi ? dpi : 96) / 96.0f;
}
}  // namespace

DesktopLyricsWindow::DesktopLyricsWindow(
    HWND main_window, flutter::BinaryMessenger* messenger)
    : main_window_(main_window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "music.sylphy/desktop_lyrics",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "permission") {
      result->Success(flutter::EncodableValue(true));
    } else if (call.method_name() == "hide") {
      Hide();
      result->Success();
    } else if (call.method_name() == "show") {
      const auto* values = call.arguments()
                               ? std::get_if<flutter::EncodableMap>(call.arguments())
                               : nullptr;
      const auto* text = values ? Value(*values, "text") : nullptr;
      const auto* color = values ? Value(*values, "color") : nullptr;
      const auto* size = values ? Value(*values, "fontSize") : nullptr;
      const auto* string = text ? std::get_if<std::string>(text) : nullptr;
      const auto* argb = color ? std::get_if<int32_t>(color) : nullptr;
      const auto* font = size ? std::get_if<double>(size) : nullptr;
      if (!string || !argb || !font || !std::isfinite(*font) ||
          *font < 12 || *font > 40) {
        result->Error("lyrics_arguments", "Invalid desktop lyrics settings");
        return;
      }
      // Bound native drawing work without splitting a UTF-8 sequence.
      text_ = WideText(*string);
      if (text_.size() > 4096) {
        text_.resize(4096);
        if (text_.back() >= 0xd800 && text_.back() <= 0xdbff) text_.pop_back();
      }
      const bool reveal_controls = !window_ || !IsWindowVisible(window_) ||
                                   color_ != static_cast<DWORD>(*argb) ||
                                   font_size_ != *font;
      color_ = static_cast<DWORD>(*argb);
      font_size_ = *font;
      const bool ready = EnsureWindow();
      if (ready && reveal_controls) ShowControls(false);
      if (ready && Render()) {
        ShowWindow(window_, SW_SHOWNOACTIVATE);
        result->Success();
      } else {
        Hide();
        result->Error("lyrics_window", "Desktop lyrics window unavailable");
      }
    } else {
      result->NotImplemented();
    }
  });
}

DesktopLyricsWindow::~DesktopLyricsWindow() {
  channel_->SetMethodCallHandler(nullptr);
  if (window_) {
    KillTimer(window_, kIdleTimer);
    KillTimer(window_, kFadeTimer);
    SavePosition();
    DestroyWindow(window_);
  }
  if (graphics_token_) Gdiplus::GdiplusShutdown(graphics_token_);
}

bool DesktopLyricsWindow::EnsureWindow() {
  if (window_) return true;
  if (!graphics_token_) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&graphics_token_, &input, nullptr) != Gdiplus::Ok) {
      graphics_token_ = 0;
      return false;
    }
  }
  WNDCLASSEXW cls{sizeof(WNDCLASSEXW)};
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpfnWndProc = WindowProc;
  cls.lpszClassName = kWindowClass;
  cls.hCursor = LoadCursorW(nullptr, IDC_SIZEALL);
  if (!RegisterClassExW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  const RECT work = WorkArea(main_window_);
  const float scale = Scale(main_window_);
  const int width = std::min(static_cast<int>(800 * scale),
                             static_cast<int>(work.right - work.left));
  RECT frame{work.left + (work.right - work.left - width) / 2,
             work.bottom - static_cast<LONG>(160 * scale), 0, 0};
  RECT saved{};
  DWORD bytes = sizeof(saved);
  if (RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, L"Position", RRF_RT_REG_BINARY,
                   nullptr, &saved, &bytes) == ERROR_SUCCESS &&
      bytes == sizeof(saved)) {
    frame = saved;
  }
  window_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWindowClass, L"Sylphy Music Lyrics", WS_POPUP, frame.left, frame.top,
      width, static_cast<int>(100 * scale), nullptr, nullptr,
      GetModuleHandleW(nullptr), this);
  return window_ != nullptr;
}

bool DesktopLyricsWindow::Render() {
  if (!window_) return false;
  const float scale = Scale(window_);
  const RECT work = WorkArea(window_);
  const int width = std::max(1, std::min(static_cast<int>(800 * scale),
                                       static_cast<int>(work.right - work.left)));
  const float font_pixels = static_cast<float>(font_size_) * scale;
  const int height = std::max(1, std::min(
      static_cast<int>(font_pixels * 2.8f + 24 * scale),
      static_cast<int>(work.bottom - work.top)));
  RECT frame{};
  GetWindowRect(window_, &frame);
  POINT destination{
      std::clamp(frame.left, work.left, work.right - width),
      std::clamp(frame.top, work.top, work.bottom - height)};
  SIZE dimensions{width, height};

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HDC dc = CreateCompatibleDC(nullptr);
  if (!dc) return false;
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!bitmap || !pixels) {
    if (bitmap) DeleteObject(bitmap);
    DeleteDC(dc);
    return false;
  }
  HGDIOBJ previous = SelectObject(dc, bitmap);
  bool painted = false;
  {
    // GDI+ writes premultiplied alpha directly into the top-down DIB consumed
    // by UpdateLayeredWindow, including anti-aliased text and rounded corners.
    Gdiplus::Bitmap surface(width, height, width * 4, PixelFormat32bppPARGB,
                            static_cast<BYTE*>(pixels));
    Gdiplus::Graphics graphics(&surface);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    const Gdiplus::Color foreground(color_);
    const bool light_text = foreground.GetR() * 299 + foreground.GetG() * 587 +
                                foreground.GetB() * 114 >= 128000;
    const BYTE background = light_text ? 18 : 245;
    Gdiplus::SolidBrush panel(Gdiplus::Color(static_cast<BYTE>(190 * controls_opacity_),
                                            background, background, background));
    const float w = static_cast<float>(width);
    const float h = static_cast<float>(height);
    const float radius = std::min(16 * scale, std::min(w, h) / 2);
    Gdiplus::GraphicsPath shape;
    shape.AddArc(0.0f, 0.0f, radius, radius, 180.0f, 90.0f);
    shape.AddArc(w - radius - 1, 0.0f, radius, radius, 270.0f, 90.0f);
    shape.AddArc(w - radius - 1, h - radius - 1, radius, radius, 0.0f, 90.0f);
    shape.AddArc(0.0f, h - radius - 1, radius, radius, 90.0f, 90.0f);
    shape.CloseFigure();
    graphics.FillPath(&panel, &shape);
    Gdiplus::FontFamily preferred_font(L"Microsoft YaHei UI");
    const auto* family = preferred_font.GetLastStatus() == Gdiplus::Ok
                             ? &preferred_font
                             : Gdiplus::FontFamily::GenericSansSerif();
    Gdiplus::Font font(family, font_pixels, Gdiplus::FontStyleBold,
                       Gdiplus::UnitPixel);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    Gdiplus::SolidBrush ink(foreground);
    const Gdiplus::RectF area(16 * scale, 8 * scale,
                              std::max(1.0f, w - 68 * scale),
                              std::max(1.0f, h - 16 * scale));
    const auto status = graphics.DrawString(text_.c_str(), -1, &font, area,
                                             &format, &ink);
    Gdiplus::Pen close_pen(Gdiplus::Color(
                                         static_cast<BYTE>(230 * controls_opacity_),
                                         light_text ? 235 : 30,
                                         light_text ? 235 : 30,
                                         light_text ? 235 : 30), 2 * scale);
    const float x = w - 26 * scale;
    const float y = h / 2;
    graphics.DrawLine(&close_pen, x - 5 * scale, y - 5 * scale,
                       x + 5 * scale, y + 5 * scale);
    graphics.DrawLine(&close_pen, x - 5 * scale, y + 5 * scale,
                       x + 5 * scale, y - 5 * scale);
    graphics.Flush(Gdiplus::FlushIntentionSync);
    POINT source{};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    painted = status == Gdiplus::Ok &&
              UpdateLayeredWindow(window_, nullptr, &destination, &dimensions,
                                   dc, &source, 0, &blend, ULW_ALPHA) != FALSE;
  }
  SelectObject(dc, previous);
  DeleteObject(bitmap);
  DeleteDC(dc);
  if (painted) {
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                  SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  return painted;
}

void DesktopLyricsWindow::ShowControls(bool redraw) {
  if (!window_) return;
  KillTimer(window_, kFadeTimer);
  fade_started_ = 0;
  const bool changed = controls_opacity_ < 1.0f;
  controls_opacity_ = 1.0f;
  SetTimer(window_, kIdleTimer, kControlsIdleMs, nullptr);
  if (changed && redraw) Render();
}

void DesktopLyricsWindow::SavePosition() {
  RECT frame{};
  if (window_ && GetWindowRect(window_, &frame)) {
    RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, L"Position", REG_BINARY,
                    &frame, sizeof(frame));
  }
}

void DesktopLyricsWindow::Hide() {
  if (!window_) return;
  KillTimer(window_, kIdleTimer);
  KillTimer(window_, kFadeTimer);
  fade_started_ = 0;
  controls_opacity_ = 1.0f;
  tracking_mouse_ = false;
  has_mouse_point_ = false;
  TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_CANCEL | TME_LEAVE, window_, 0};
  TrackMouseEvent(&tracking);
  dragging_ = false;
  if (GetCapture() == window_) ReleaseCapture();
  SavePosition();
  ShowWindow(window_, SW_HIDE);
}

void DesktopLyricsWindow::Dismiss() {
  Hide();
  channel_->InvokeMethod("dismissed", std::make_unique<flutter::EncodableValue>());
}

bool DesktopLyricsWindow::InCloseButton(int x) const {
  RECT client{};
  GetClientRect(window_, &client);
  return controls_opacity_ > 0.0f && x >= client.right - static_cast<int>(48 * Scale(window_));
}

LRESULT CALLBACK DesktopLyricsWindow::WindowProc(HWND window, UINT message,
                                                 WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<DesktopLyricsWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<DesktopLyricsWindow*>(create->lpCreateParams);
    self->window_ = window;
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self) return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_LBUTTONDOWN:
      if (self->InCloseButton(GET_X_LPARAM(lparam))) {
        self->Dismiss();
      } else {
        self->ShowControls();
        self->dragging_ = true;
        GetCursorPos(&self->drag_start_);
        GetWindowRect(window, &self->drag_frame_);
        SetCapture(window);
      }
      return 0;
    case WM_MOUSEMOVE: {
      POINT mouse{};
      GetCursorPos(&mouse);
      // Repaints can produce mouse messages without actual pointer movement.
      // They must not repeatedly restart the idle countdown during a fade.
      if (!self->has_mouse_point_ || mouse.x != self->last_mouse_point_.x ||
          mouse.y != self->last_mouse_point_.y) {
        self->ShowControls();
      }
      self->last_mouse_point_ = mouse;
      self->has_mouse_point_ = true;
      if (!self->tracking_mouse_) {
        TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_LEAVE, window, 0};
        self->tracking_mouse_ = TrackMouseEvent(&tracking) != FALSE;
      }
      if (self->dragging_ && GetCapture() == window) {
        POINT point{};
        GetCursorPos(&point);
        SetWindowPos(window, HWND_TOPMOST,
                      self->drag_frame_.left + point.x - self->drag_start_.x,
                      self->drag_frame_.top + point.y - self->drag_start_.y,
                      0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      self->tracking_mouse_ = false;
      return 0;
    case WM_TIMER:
      if (wparam == kIdleTimer) {
        KillTimer(window, kIdleTimer);
        if (self->dragging_) {
          self->ShowControls();
        } else if (IsWindowVisible(window)) {
          self->fade_started_ = GetTickCount64();
          SetTimer(window, kFadeTimer, 16, nullptr);
        }
        return 0;
      }
      if (wparam == kFadeTimer) {
        if (!self->fade_started_) return 0;
        const auto elapsed = GetTickCount64() - self->fade_started_;
        self->controls_opacity_ = 1.0f -
            std::min(1.0f, static_cast<float>(elapsed) / kControlsFadeMs);
        if (elapsed >= kControlsFadeMs) {
          KillTimer(window, kFadeTimer);
          self->fade_started_ = 0;
        }
        self->Render();
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (self->dragging_) {
        self->dragging_ = false;
        self->ShowControls();
        ReleaseCapture();
        self->Render();
        self->SavePosition();
      }
      return 0;
    case WM_CAPTURECHANGED:
      if (self->dragging_) self->ShowControls();
      self->dragging_ = false;
      return 0;
    case WM_SETCURSOR: {
      POINT point{};
      GetCursorPos(&point);
      ScreenToClient(window, &point);
      SetCursor(LoadCursorW(nullptr,
                            self->InCloseButton(point.x) ? IDC_HAND : IDC_SIZEALL));
      return TRUE;
    }
    case WM_DPICHANGED: {
      const auto* frame = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, frame->left, frame->top, 0, 0,
                    SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
      self->Render();
      return 0;
    }
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      if (IsWindowVisible(window)) self->Render();
      return 0;
    case WM_CLOSE:
      self->Dismiss();
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      BeginPaint(window, &paint);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_NCDESTROY:
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      self->window_ = nullptr;
      break;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
