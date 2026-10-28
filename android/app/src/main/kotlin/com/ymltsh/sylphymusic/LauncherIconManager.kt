package com.ymltsh.sylphymusic

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray

/** Owns launcher activity-alias state; no dependency on Flutter's widget state. */
internal class LauncherIconManager(private val activity: Activity) {
    private data class Icon(val id: String, val label: String, val preview: String) {
        val alias: String get() = if (id == "default") "LauncherIconDefault" else "LauncherIcon_$id"
    }

    private val icons: List<Icon> by lazy {
        val json = activity.assets.open("launcher_icons.json")
            .bufferedReader(Charsets.UTF_8).use { JSONArray(it.readText()) }
        buildList {
            add(Icon("default", "微风与低音（默认）", "assets/icon.png"))
            for (index in 0 until json.length()) {
                val item = json.getJSONObject(index)
                val id = item.getString("id")
                require(id.matches(Regex("alt_[a-f0-9]{12}"))) { "Invalid icon id: $id" }
                add(Icon(id, item.getString("label"), item.getString("preview")))
            }
        }
    }

    private fun component(icon: Icon): ComponentName =
        ComponentName(activity.packageName, "${activity.packageName}.${icon.alias}")

    private fun enabled(icon: Icon): Boolean = when (
        activity.packageManager.getComponentEnabledSetting(component(icon))
    ) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> false
        else -> icon.id == "default" // Manifest default only enables original icon.
    }

    private fun current(): String? = icons.firstOrNull(::enabled)?.id

    fun options(): Map<String, Any> {
        // An app update can remove a previously selected alias. Repair the
        // default entry when none of the installed aliases is enabled.
        val selected = current() ?: run {
            select("default")
            "default"
        }
        return mapOf(
            "selected" to selected,
            "options" to icons.map { mapOf("id" to it.id, "label" to it.label, "preview" to it.preview) },
        )
    }

    fun select(id: String) {
        val target = icons.firstOrNull { it.id == id }
            ?: throw IllegalArgumentException("此版本未包含该图标")
        if (current() == id && icons.count(::enabled) == 1) return
        val manager = activity.packageManager
        if (Build.VERSION.SDK_INT >= 33) {
            // Atomic on Android 13+: there is never a window without a launcher icon.
            manager.setComponentEnabledSettings(
                icons.map { icon ->
                    PackageManager.ComponentEnabledSetting(
                        component(icon),
                        if (icon.id == target.id) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
            )
        } else {
            // Pre-33: enable the new alias before disabling the old ones.
            manager.setComponentEnabledSetting(
                component(target), PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            icons.filter { it.id != target.id }.forEach { icon ->
                manager.setComponentEnabledSetting(
                    component(icon), PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }
}
