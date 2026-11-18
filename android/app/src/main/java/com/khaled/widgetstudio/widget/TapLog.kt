package com.khaled.widgetstudio.widget

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/**
 * Every widget tap with what became of it (ADR-028): the proof that a tap reached the app, kept on
 * the phone only and shown in Diagnostics. A tap that never appears here never left the launcher.
 */
object TapLog {
    data class Entry(val time: Long, val action: String, val arg: String, val widget: Int, val result: String, val error: String?)

    private const val KEY = "entries"
    private const val LIMIT = 40

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences("tap_log", Context.MODE_PRIVATE)

    @Synchronized
    fun add(context: Context, action: String, arg: String, widget: Int, result: String, error: String? = null) {
        val list = entries(context).toMutableList()
        list.add(0, Entry(System.currentTimeMillis(), action, arg, widget, result, error))
        val array = JSONArray()
        list.take(LIMIT).forEach { entry ->
            array.put(JSONObject().put("t", entry.time).put("a", entry.action).put("g", entry.arg).put("w", entry.widget).put("r", entry.result).put("e", entry.error ?: ""))
        }
        prefs(context).edit().putString(KEY, array.toString()).apply()
    }

    fun entries(context: Context): List<Entry> {
        val array = runCatching { JSONArray(prefs(context).getString(KEY, "[]") ?: "[]") }.getOrNull() ?: return emptyList()
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            Entry(item.optLong("t"), item.optString("a"), item.optString("g"), item.optInt("w"), item.optString("r"), item.optString("e").ifEmpty { null })
        }
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }
}

/**
 * The widget's opening taps pass through here: it logs the tap, starts the target and closes. A
 * target that no installed app handles shows the hint instead of a tap that seems to do nothing.
 */
class TapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent.getStringExtra(EXTRA_ACTION) ?: ""
        val arg = intent.getStringExtra(EXTRA_ARG) ?: ""
        @Suppress("DEPRECATION")
        val target = intent.getParcelableExtra<Intent>(EXTRA_TARGET)
        if (target == null) {
            TapLog.add(this, action, arg, 0, "no target", "nothing to open")
        } else {
            try {
                startActivity(target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                TapLog.add(this, action, arg, 0, "opened " + (target.component?.shortClassName ?: target.action ?: "app"))
            } catch (error: ActivityNotFoundException) {
                TapLog.add(this, action, arg, 0, "failed", error.message ?: "no app handles this")
                ActionRouter.showHint(this, action)
            } catch (error: SecurityException) {
                TapLog.add(this, action, arg, 0, "failed", error.message ?: "not allowed")
                ActionRouter.showHint(this, action)
            }
        }
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    companion object {
        private const val EXTRA_ACTION = "tap.action"
        private const val EXTRA_ARG = "tap.arg"
        private const val EXTRA_TARGET = "tap.target"

        fun intent(context: Context, action: String, arg: String?, target: Intent): Intent = Intent(context, TapActivity::class.java)
            .putExtra(EXTRA_ACTION, action).putExtra(EXTRA_ARG, arg ?: "").putExtra(EXTRA_TARGET, target)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
