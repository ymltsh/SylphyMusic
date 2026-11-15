#include <jni.h>
#include <dlfcn.h>
#include <cstdint>
#include <string>
#include <vector>
#include <utility>
#include <chrono>
#include <thread>
#include <deque>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cstdlib>

// Only the stable public libmpv client ABI is used. The shared library is the
// same ABI-specific libmpv bundled by media_kit_libs_android_audio.
struct mpv_handle;
struct mpv_event { int event_id; int error; uint64_t reply_userdata; void* data; };
struct mpv_event_end_file { int reason; int error; int64_t playlist_entry_id;
    int64_t playlist_insert_id; int playlist_insert_num_entries; };
struct mpv_event_log_message { const char* prefix; const char* level; const char* text; int log_level; };
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
    int (*request_logs)(mpv_handle*, const char*);
    char* (*get_string)(mpv_handle*, const char*);
    void (*free_mem)(void*);
    bool loaded = false, enabled = false, diagnostics = false, armed = false;
    bool ended = false, error = false, seek = false, restarted = false;
    double next_start = 0, filtered_end = -1, filtered_frame = 0.02;
    int reconfigs = 0, log_events = 0;
    uint64_t diagnostic_sequence = 0;
    std::deque<std::string> records;
};
static double number(Engine* e, const char* property, double fallback = -1) {
    double value = fallback; e->get(e->handle, property, 5, &value); return value;
}
static std::string token(Engine* e, const char* property) {
    char* raw = e->get_string(e->handle, property);
    std::string value = raw ? raw : "unknown"; if (raw) e->free_mem(raw);
    if (value.size() > 32 || value.empty()) return "unknown";
    for (char c : value) if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) return "unknown";
    return value;
}
static void record(Engine* e, const char* event, int fade_ms = 0, double requested = -1) {
    if (!e->diagnostics) return;
    std::ostringstream out;
    double position = number(e,"time-pos");
    out << "{\"event\":\"" << event << "\",\"native_seq\":" << ++e->diagnostic_sequence
        << ",\"native_uptime_ms\":" << std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()
        << ",\"resume_ms\":" << static_cast<int64_t>(requested*1000)
        << ",\"position_ms\":" << (std::isfinite(position) ? static_cast<int64_t>(position*1000) : -1)
        << ",\"sample_rate\":" << static_cast<int>(number(e,"audio-out-params/samplerate",0))
        << ",\"channels\":" << static_cast<int>(number(e,"audio-out-params/channel-count",0))
        << ",\"audio_mode\":\"" << token(e,"current-ao") << "\",\"format\":\"" << token(e,"audio-out-params/format")
        << "\",\"declick\":" << (e->enabled ? "true":"false") << ",\"output_reconfigs\":" << e->reconfigs
        << ",\"fade_ms\":" << fade_ms << ",\"log_events\":" << e->log_events << ",\"filter_pts_ms\":" << static_cast<int64_t>(e->filtered_end*1000) << "}";
    if (e->records.size() == 128) e->records.pop_front();
    e->records.push_back(out.str());
}
static void events(Engine* e) {
    for (int i = 0; i < 512; ++i) {
        auto* event = e->wait(e->handle,0);
        if (!event || event->event_id == 0) break;
        switch (event->event_id) {
        case 2: {
            // Only numeric timing from our ashowinfo filter is consumed. No raw
            // mpv/FFmpeg text (which can contain URLs or metadata) leaves JNI.
            ++e->log_events;
            auto* log = static_cast<mpv_event_log_message*>(event->data);
            if (!log || !log->text) break;
            const char *pts = strstr(log->text,"pts_time:"), *rate = strstr(log->text,"rate:"), *samples = strstr(log->text,"nb_samples:");
            if (pts && rate && samples) {
                double t = strtod(pts+9,nullptr), r = strtod(rate+5,nullptr), n = strtod(samples+11,nullptr);
                if (std::isfinite(t) && r >= 8000 && r <= 768000 && n > 0 && n < r*2) {
                    e->filtered_frame = n/r; e->filtered_end = t+n/r;
                }
            }
            break;
        }
        case 6: e->loaded = false; break;
        case 8: e->loaded = true; record(e,"mpv_file_loaded"); break;
        case 18: ++e->reconfigs; record(e,"mpv_audio_reconfig"); break;
        case 20: e->seek = true; record(e,"mpv_seek"); break;
        case 21: e->restarted = true; e->armed = false; record(e,"mpv_playback_restart"); break;
        case 7: {
            auto* end = static_cast<mpv_event_end_file*>(event->data);
            if (end && end->reason == 0 && e->loaded) e->ended = true;
            if (end && end->reason == 4) e->error = true;
            e->loaded = false; break;
        }
        case 5: if (event->error < 0) e->error = true; break;
        }
    }
}
static int command(Engine* e, std::initializer_list<const char*> args) {
    std::vector<const char*> values(args); values.push_back(nullptr);
    return e->command_sync(e->handle,values.data());
}
static std::string seconds(double value) {
    std::ostringstream out; out.imbue(std::locale::classic()); out << std::fixed << std::setprecision(9) << std::max(0.0,value); return out.str();
}
static bool envelope(Engine* e, double position) {
    if (!e->enabled) { e->set(e->handle,"af",""); return true; }
    // fix-pts=no preserves source timestamps. Exact-seek preroll remains silent
    // until the target PTS, so trimming preroll cannot discard the fade-in.
    const std::string graph = "@sylphy_declick:lavfi=graph=[afade@enter=t=in:st=" + seconds(position) +
        ":d=0.020:curve=hsin,afade@leave=t=out:st=1000000000:d=0.012:curve=hsin,ashowinfo]:fix-pts=no";
    e->filtered_end = -1; e->armed = true;
    if (e->set(e->handle,"af",graph.c_str()) < 0) {
        e->enabled = false; e->set(e->handle,"af",""); record(e,"declick_filter_unavailable"); return false;
    }
    record(e,"declick_fade_in_armed",20); return true;
}
static bool pause_requested(JNIEnv* env, jobject owner) {
    jclass type = env->GetObjectClass(owner);
    jfieldID field = env->GetFieldID(type,"pauseRequested","Z");
    bool paused = env->GetBooleanField(owner,field); env->DeleteLocalRef(type); return paused;
}
static void fade_out(Engine* e, JNIEnv* env, jobject owner) {
    int paused = 1; e->get(e->handle,"pause",3,&paused);
    if (!e->enabled || !e->loaded || paused) return;
    events(e);
    const double now = number(e,"time-pos",0);
    if (e->filtered_end < now-0.020 || e->filtered_end > now+2.0) { record(e,"declick_no_filter_clock"); return; }
    // Schedule in the PCM timeline, beyond the last processed frame. Waiting
    // below only gates the seek; afade computes every gain value per sample.
    const double start = e->filtered_end + std::max(0.020,e->filtered_frame*2);
    const std::string at = seconds(start);
    if (command(e,{"af-command","sylphy_declick","st",at.c_str(),"afade@leave"}) < 0) {
        record(e,"declick_fade_out_rejected"); return;
    }
    record(e,"declick_fade_out_armed",12);
    const auto deadline = std::chrono::steady_clock::now()+std::chrono::milliseconds(1000);
    while (std::chrono::steady_clock::now()<deadline) {
        events(e);
        if (number(e,"time-pos") >= start+0.012) { record(e,"declick_fade_out_complete",12); return; }
        if (pause_requested(env,owner)) { record(e,"declick_fade_out_interrupted"); return; }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    record(e,"declick_fade_out_timeout");
}
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
    LOAD(request_logs,"mpv_request_log_messages") LOAD(get_string,"mpv_get_property_string") LOAD(free_mem,"mpv_free")
    LOAD(wait, "mpv_wait_event") LOAD(destroy, "mpv_terminate_destroy")
#undef LOAD
    // AudioTrack's FFmpeg JNI access needs the application's actual VM.
    auto set_vm = reinterpret_cast<int (*)(void*)>(dlsym(e->library, "mpv_lavc_set_java_vm"));
    JavaVM* vm = nullptr; env->GetJavaVM(&vm);
    if (set_vm) set_vm(vm);
    else {
        // Current mpv uses FFmpeg's public JavaVM registration instead of the
        // historical media-kit-specific mpv_lavc_set_java_vm extension.
        void* avcodec = dlopen("libavcodec.so",RTLD_NOW|RTLD_LOCAL);
        auto register_vm = avcodec ? reinterpret_cast<int (*)(void*,void*)>(dlsym(avcodec,"av_jni_set_java_vm")) : nullptr;
        if (!register_vm || register_vm(vm,nullptr)<0) { if (avcodec) dlclose(avcodec); dlclose(e->library); delete e; fail(env); return 0; }
        dlclose(avcodec);
    }
    e->handle = e->create();
    if (!e->handle) { dlclose(e->library); delete e; fail(env); return 0; }
    for (auto pair : {std::pair{"config", "no"}, {"vid", "no"}, {"idle", "yes"},
         {"pause", "yes"}, {"keep-open", "no"}, {"terminal", "no"},
         {"msg-level", "all=no,ffmpeg=v,lavfi=v"}, {"ao", "audiotrack,opensles"},
         {"gapless-audio", "no"}, {"sub-auto", "no"}, {"audio-pitch-correction", "yes"},
         {"network-timeout", "15"}}) e->option(e->handle, pair.first, pair.second);
    if (e->initialize(e->handle) < 0) {
        e->destroy(e->handle); dlclose(e->library); delete e; fail(env); return 0;
    }
    e->request_logs(e->handle,"v");
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
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_set(JNIEnv* env, jobject owner, jlong ptr, jstring name, jstring value) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    auto key=utf(env,name), text=utf(env,value);
    if (key=="sylphy-declick") {
        const bool enabled=text=="yes";
        if (e->enabled==enabled) return;
        e->enabled=enabled;

        // Enabling takes effect on the next start/seek; never rebuild live
        // output merely to flip an A/B switch.
        record(e,enabled ? "declick_enabled":"declick_disabled"); return;
    }
    if (key=="sylphy-diagnostics") {
        e->diagnostics=text=="yes"; e->records.clear(); record(e,"native_audio_snapshot"); return;
    }
    if (key=="start") e->next_start=strtod(text.c_str(),nullptr);
    if (key=="pause" && text=="no" && !e->enabled) e->set(e->handle,"af","");
    if (key=="pause" && text=="no" && e->enabled && e->loaded && !e->armed) {
        int paused=0; e->get(e->handle,"pause",3,&paused);
        if (paused) {
            double position=number(e,"time-pos",0); envelope(e,position);
            auto target=seconds(position); command(e,{"seek",target.c_str(),"absolute+exact"});
            record(e,"declick_resume",20);
        }
    }
    if (e->set(e->handle,key.c_str(),text.c_str())<0) fail(env);
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_command(JNIEnv* env, jobject owner, jlong ptr, jobjectArray args) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    std::vector<std::string> strings;
    for (jsize i = 0; i < env->GetArrayLength(args); ++i) {
        auto value = static_cast<jstring>(env->GetObjectArrayElement(args, i));
        strings.push_back(utf(env, value)); env->DeleteLocalRef(value);
    }
    std::vector<const char*> values;
    for (auto& s : strings) values.push_back(s.c_str());
    values.push_back(nullptr);
    if (!strings.empty() && strings[0]=="seek" && strings.size()>=3 && strings[2]=="absolute+exact" && e->enabled) {
        record(e,"seek_requested",0,strtod(strings[1].c_str(),nullptr)); fade_out(e,env,owner);
        e->set(e->handle,"pause","yes");
        envelope(e,strtod(strings[1].c_str(),nullptr));
        e->ended=false; e->error=false; e->seek=false; e->restarted=false;
        if (e->command_sync(e->handle,values.data())<0) fail(env);
        if (!pause_requested(env,owner)) e->set(e->handle,"pause","no");
        return;
    }
    if (!strings.empty() && strings[0]=="seek" && !e->enabled) e->set(e->handle,"af","");
    if (!strings.empty() && strings[0]=="loadfile") {
        envelope(e,e->next_start);
        e->ended=false; e->error=false; e->seek=false; e->restarted=false;
        record(e,"load_requested");
    }
    if (e->command(e->handle, 0, values.data()) < 0) fail(env);
    if (!strings.empty() && (strings[0] == "loadfile" || strings[0] == "stop")) e->loaded = false;
}
extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_sample(JNIEnv* env, jobject, jlong ptr) {
    auto* e = reinterpret_cast<Engine*>(ptr);
    events(e);
    double pos = -1, duration = -1; int paused = 1, buffering = 0;
    e->get(e->handle, "time-pos", 5, &pos); // MPV_FORMAT_DOUBLE
    e->get(e->handle, "duration", 5, &duration);
    e->get(e->handle, "pause", 3, &paused); // MPV_FORMAT_FLAG
    e->get(e->handle, "paused-for-cache", 3, &buffering);
    double values[] = {pos * 1000, duration * 1000, double(paused), double(buffering), double(e->ended), double(e->error), double(e->loaded), double(e->seek), double(e->restarted), double(e->enabled)};
    e->ended=false; e->error=false; e->seek=false; e->restarted=false;
    auto result = env->NewDoubleArray(10); env->SetDoubleArrayRegion(result, 0, 10, values); return result;
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_diagnostics(JNIEnv* env,jobject,jlong ptr) {
    auto* e=reinterpret_cast<Engine*>(ptr); std::string json="[";
    for (auto& record:e->records) { if (json.size()>1) json+=","; json+=record; }
    json+="]"; e->records.clear(); return env->NewStringUTF(json.c_str());
}
extern "C" JNIEXPORT void JNICALL
Java_com_ymltsh_sylphymusic_playback_NativeMpvEngine_destroy(JNIEnv*, jobject, jlong ptr) {
    auto* e = reinterpret_cast<Engine*>(ptr); e->destroy(e->handle); dlclose(e->library); delete e;
}
