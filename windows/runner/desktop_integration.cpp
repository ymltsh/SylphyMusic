#include "desktop_integration.h"
#include <SystemMediaTransportControlsInterop.h>
#include "resource.h"

namespace {
constexpr UINT kTray = WM_APP + 40;
constexpr UINT kMedia = WM_APP + 41;
std::string StringValue(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return "";
  auto value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}
}

DesktopIntegration::DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "music.sylphy/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "capabilities") {
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("mediaControls"), flutter::EncodableValue(static_cast<bool>(controls_))},
        {flutter::EncodableValue("tray"), flutter::EncodableValue(tray_ready_)}}));
      return;
    }
    if (call.method_name() != "update") { result->NotImplemented(); return; }
    try {
      auto values = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (values && controls_) {
        auto updater = controls_.DisplayUpdater();
        updater.Type(winrt::Windows::Media::MediaPlaybackType::Music);
        auto music = updater.MusicProperties();
        music.Title(winrt::to_hstring(StringValue(*values, "title")));
        music.Artist(winrt::to_hstring(StringValue(*values, "artist")));
        music.AlbumTitle(winrt::to_hstring(StringValue(*values, "album")));
        updater.Update();
        controls_.PlaybackStatus(StringValue(*values, "state") == "playing"
            ? winrt::Windows::Media::MediaPlaybackStatus::Playing
            : winrt::Windows::Media::MediaPlaybackStatus::Paused);
      }
      result->Success();
    } catch (...) { result->Error("media_update", "System media controls could not be updated"); }
  });
  tray_.cbSize = sizeof(tray_); tray_.hWnd = window_; tray_.uID = 1;
  tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP; tray_.uCallbackMessage = kTray;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_.szTip, L"Sylphy Music");
  tray_ready_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
  try {
    auto interop = winrt::get_activation_factory<winrt::Windows::Media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(window_, winrt::guid_of<decltype(controls_)>(),
        winrt::put_abi(controls_)));
    controls_.IsEnabled(true); controls_.IsPlayEnabled(true); controls_.IsPauseEnabled(true);
    controls_.IsNextEnabled(true); controls_.IsPreviousEnabled(true); controls_.IsStopEnabled(true);
    button_token_ = controls_.ButtonPressed([window](auto const&, auto const& args) {
      PostMessage(window, kMedia, static_cast<WPARAM>(args.Button()), 0);
    });
  } catch (...) { controls_ = nullptr; }
}

DesktopIntegration::~DesktopIntegration() {
  if (controls_) { controls_.ButtonPressed(button_token_); controls_.IsEnabled(false); }
  if (tray_ready_) Shell_NotifyIconW(NIM_DELETE, &tray_);
  channel_->SetMethodCallHandler(nullptr);
}
void DesktopIntegration::Send(const char* action) {
  channel_->InvokeMethod(action, std::make_unique<flutter::EncodableValue>());
}
bool DesktopIntegration::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLOSE && tray_ready_) { ShowWindow(window_, SW_HIDE); return true; }
  if (message == kMedia) {
    using Button = winrt::Windows::Media::SystemMediaTransportControlsButton;
    switch (static_cast<Button>(wparam)) {
      case Button::Play: Send("play"); break;
      case Button::Pause: Send("pause"); break;
      case Button::Next: Send("next"); break;
      case Button::Previous: Send("previous"); break;
      case Button::Stop: Send("pause"); break;
      default: break;
    }
    return true;
  }
  if (message == kTray) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_);
    } else if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, 1, L"Show Sylphy Music");
      AppendMenuW(menu, MF_STRING, 2, L"Play / Pause");
      AppendMenuW(menu, MF_STRING, 3, L"Next");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, 4, L"Exit");
      POINT point; GetCursorPos(&point); SetForegroundWindow(window_);
      UINT item = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
          point.x, point.y, 0, window_, nullptr); DestroyMenu(menu);
      if (item == 1) { ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_); }
      if (item == 2) Send("toggle");
      if (item == 3) Send("next");
      if (item == 4) Send("quit");
    }
    return true;
  }
  return false;
}
