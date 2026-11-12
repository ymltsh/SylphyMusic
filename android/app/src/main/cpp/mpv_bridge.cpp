#include <jni.h>
#include <dlfcn.h>
#include <cstdint>
#include <string>
#include <vector>
#include <utility>
#include <chrono>

// Only the stable public libmpv client ABI is used. The shared library is the
// same ABI-specific libmpv bundled by media_kit_libs_android_audio.
struct mpv_handle;
struct mpv_event { int event_id; int error; uint64_t reply_userdata; void* data; };
struct mpv_event_end_file { int reason; int error; int64_t playlist_entry_id;
    int64_t playlist_insert_id; int playlist_insert_num_entries; };
struct Engine {
    void* library = nullptr;
    mpv_handle* handle = nullptr;
    mpv_handle* (*create)();
    int (*option)(mpv_handle*, const char*, const char*);
    int (*initialize)(mpv_handle*);
    int (*set)(mpv_handle*, const char*, const char*);
    int (*get)(mpv_handle*, const char*, int, void*);
    int (*command)(mpv_handle*, uint64_t, const char**);
    int (*command_sync)(mpv_handle*, const char**);
    mpv_event* (*wait)(mpv_handle*, double);
    void (*destroy)(mpv_handle*);
    bool loaded = false;
};
static void fail(JNIEnv* env) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Native audio unavailable");
}
static std::string utf(JNIEnv* env, jstring value) {
    const char* s = env->GetStringUTFChars(value, nullptr);
    std::string result(s); env->ReleaseStringUTFChars(value, s); return result;
}
extern "C" JNIEXPORT jlong JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_create(JNIEnv* env, jobject) {
    auto* e = new Engine();
    e->library = dlopen("libmpv.so", RTLD_NOW | RTLD_LOCAL);
    if (!e->library) { delete e; fail(env); return 0; }
#define LOAD(field, symbol) e->field = reinterpret_cast<decltype(e->field)>(dlsym(e->library, symbol)); if (!e->field) { dlclose(e->library); delete e; fail(env); return 0; }
    LOAD(create, "mpv_create") LOAD(option, "mpv_set_option_string")
    LOAD(initialize, "mpv_initialize") LOAD(set, "mpv_set_property_string")
    LOAD(get, "mpv_get_property") LOAD(command, "mpv_command_async")
    LOAD(command_sync, "mpv_command")
    LOAD(wait, "mpv_wait_event") LOAD(destroy, "mpv_terminate_destroy")
#undef LOAD
    // AudioTrack's FFmpeg JNI access needs the application's actual VM.
    auto set_vm = reinterpret_cast<int (*)(void*)>(dlsym(e->library, "mpv_lavc_set_java_vm"));
    JavaVM* vm = nullptr; env->GetJavaVM(&vm);
    if (set_vm) set_vm(vm);
    e->handle = e->create();
    if (!e->handle) { dlclose(e->library); delete e; fail(env); return 0; }
    for (auto pair : {std::pair{"config", "no"}, {"vid", "no"}, {"idle", "yes"},
         {"pause", "yes"}, {"keep-open", "no"}, {"terminal", "no"},
         {"msg-level", "all=no"}, {"ao", "audiotrack,opensles"},
         {"gapless-audio", "no"}, {"sub-auto", "no"}, {"audio-pitch-correction", "yes"},
         {"network-timeout", "15"}}) e->option(e->handle, pair.first, pair.second);
    if (e->initialize(e->handle) < 0) {
        e->destroy(e->handle); dlclose(e->library); delete e; fail(env); return 0;
    }
    return reinterpret_cast<jlong>(e);
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_stop(JNIEnv* env, jobject, jlong ptr) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    const char* args[] = {"stop", nullptr};
    if (e->command_sync(e->handle, args) < 0) { fail(env); return; }
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline) {
        int idle = 0;
        if (e->get(e->handle, "idle-active", 3, &idle) >= 0 && idle) {
            for (int i = 0; i < 256; ++i) if (e->wait(e->handle, 0)->event_id == 0) break;
            e->loaded = false;
            return;
        }
        e->wait(e->handle, 0.05);
    }
    fail(env); // The caller must retain its lease if decoder shutdown is unconfirmed.
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_set(JNIEnv* env, jobject, jlong ptr, jstring name, jstring value) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    if (e->set(e->handle, utf(env, name).c_str(), utf(env, value).c_str()) < 0) fail(env);
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_command(JNIEnv* env, jobject, jlong ptr, jobjectArray args) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    std::vector<std::string> strings;
    for (jsize i = 0; i < env->GetArrayLength(args); ++i) {
        auto value = static_cast<jstring>(env->GetObjectArrayElement(args, i));
        strings.push_back(utf(env, value)); env->DeleteLocalRef(value);
    }
    std::vector<const char*> values;
    for (auto& s : strings) values.push_back(s.c_str());
    values.push_back(nullptr);
    if (e->command(e->handle, 0, values.data()) < 0) fail(env);
    if (!strings.empty() && (strings[0] == "loadfile" || strings[0] == "stop")) e->loaded = false;
}
extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_sample(JNIEnv* env, jobject, jlong ptr) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    double ended = 0, error = 0, seek = 0, restarted = 0;
    for (int i = 0; i < 128; ++i) {
        auto* event = e->wait(e->handle, 0);
        if (!event || event->event_id == 0) break;
        if (event->event_id == 6) e->loaded = false; // START_FILE
        if (event->event_id == 8) e->loaded = true; // FILE_LOADED
        if (event->event_id == 20) seek = 1;
        if (event->event_id == 21) restarted = 1; // PLAYBACK_RESTART after seek/rebuffer
        if (event->event_id == 7) {
            auto* end = static_cast<mpv_event_end_file*>(event->data);
            if (end && end->reason == 0 && e->loaded) ended = 1; // EOF only, never STOP/REPLACE
            if (end && end->reason == 4) error = 1;
            e->loaded = false;
        }
        if (event->event_id == 5 && event->error < 0) error = 1;
    }
    double pos = -1, duration = -1; int paused = 1, buffering = 0;
    e->get(e->handle, "time-pos", 5, &pos); // MPV_FORMAT_DOUBLE
    e->get(e->handle, "duration", 5, &duration);
    e->get(e->handle, "pause", 3, &paused); // MPV_FORMAT_FLAG
    e->get(e->handle, "paused-for-cache", 3, &buffering);
    double values[] = {pos * 1000, duration * 1000, double(paused), double(buffering), ended, error, double(e->loaded), seek, restarted};
    auto result = env->NewDoubleArray(9); env->SetDoubleArrayRegion(result, 0, 9, values); return result;
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_destroy(JNIEnv*, jobject, jlong ptr) {
    auto* e = reinterpret_cast<Engine*>(ptr); e->destroy(e->handle); dlclose(e->library); delete e;
}
