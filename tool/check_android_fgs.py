"""Exercise synthetic dataSync lifecycle scenarios on the dedicated test AVD."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="emulator-5580")
    parser.add_argument("--scenario", choices=["timeout", "overlap"], required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    sdk_adb = (
        Path(os.environ.get("ANDROID_HOME", Path.home() / "AppData/Local/Android/Sdk"))
        / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb")
    )
    adb = str(sdk_adb) if sdk_adb.is_file() else shutil.which("adb")
    if not adb:
        raise RuntimeError("Android SDK platform-tools must be installed")

    def run(*command):
        return subprocess.run([adb, "-s", args.device, *command], capture_output=True,
                              text=True, timeout=30)

    avd = run("emu", "avd", "name")
    if avd.returncode or avd.stdout.splitlines()[0] != "SylphyTest_API35":
        raise RuntimeError("This changes system test settings; use only SylphyTest_API35")
    if run("shell", "getprop", "sys.boot_completed").stdout.strip() != "1":
        raise RuntimeError("Wait for the test AVD to finish booting")
    package = "com.ymltsh.sylphymusic"
    key = "data_sync_fgs_timeout_duration"
    previous = run("shell", "device_config", "get", "activity_manager", key).stdout.strip()
    # Do not overwrite a caller's explicit compat override: this disposable AVD
    # uses targetSdk 35, where the change is already enabled by default.
    duration = "3000" if args.scenario == "timeout" else "60000"
    log = root / "build/test_logs" / f"lease-{args.scenario}-android.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    flutter = shutil.which("flutter")
    if not flutter:
        raise RuntimeError("Flutter must be on PATH")
    process = None
    try:
        result = run("shell", "device_config", "put", "activity_manager", key, duration)
        if result.returncode:
            raise RuntimeError("Could not configure test timeout")
        command = [flutter, "test", "--no-pub", "integration_test/sync_foreground_test.dart",
                   "-d", args.device, f"--dart-define=SYLPHY_FGS_{args.scenario.upper()}_TEST=true"]
        with log.open("w", encoding="utf-8") as output:
            process = subprocess.Popen(command, cwd=root, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            permission = background = restored = False
            deadline = time.monotonic() + 300
            while process.poll() is None:
                content = log.read_text(encoding="utf-8", errors="replace")
                if not permission and "FGS_PERMISSION_READY" in content:
                    result = run("shell", "pm", "grant", package, "android.permission.POST_NOTIFICATIONS")
                    if result.returncode:
                        raise RuntimeError("Could not grant test notification permission")
                    permission = True
                ready = "FGS_READY_BACKGROUND" if args.scenario == "timeout" else "FGS_OVERLAP_BACKGROUND"
                restore = "FGS_TIMEOUT_OBSERVED" if args.scenario == "timeout" else "FGS_OVERLAP_RESTORE"
                if not background and ready in content:
                    run("shell", "input", "keyevent", "KEYCODE_HOME")
                    if args.scenario == "overlap":
                        run("shell", "input", "keyevent", "KEYCODE_SLEEP")
                        tasks = run("shell", "dumpsys", "activity", "recents").stdout
                        task = re.search(r"Task\{[^\n]*#(\d+)[^\n]*com\.ymltsh\.sylphymusic", tasks)
                        if not task or run("shell", "am", "stack", "remove", task[1]).returncode:
                            raise RuntimeError("Could not remove synthetic test Activity")
                    background = True
                    print(f"Background transition completed: {args.scenario}", flush=True)
                if not restored and restore in content:
                    run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
                    run("shell", "wm", "dismiss-keyguard")
                    run("shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1")
                    restored = True
                if time.monotonic() > deadline:
                    raise RuntimeError("Native test exceeded five-minute deadline")
                time.sleep(0.5)
        if process.returncode or not background or not restored:
            raise RuntimeError(f"Native lifecycle check failed; see {log}")
        print(f"Passed: {log}")
    finally:
        if process is not None and process.poll() is None:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            else:
                process.terminate()
            process.wait(timeout=30)
        if previous and previous != "null":
            run("shell", "device_config", "put", "activity_manager", key, previous)
        else:
            run("shell", "device_config", "delete", "activity_manager", key)


if __name__ == "__main__":
    main()
