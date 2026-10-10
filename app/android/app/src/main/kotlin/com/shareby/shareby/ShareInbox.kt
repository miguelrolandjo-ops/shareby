package com.shareby.shareby

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Tiny native queue for links shared while Flutter isn't running.
 * ShareReceiverActivity adds to it; MainActivity hands it to Dart ("drainPending").
 */
object ShareInbox {
    private const val PREFS = "shareby_share_inbox"
    private const val KEY = "pending"

    @Synchronized
    fun add(context: Context, url: String, text: String?, choose: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY, "[]"))
        queue.put(
            JSONObject()
                .put("url", url)
                .put("text", text ?: "")
                .put("choose", choose)
                .put("receivedAt", System.currentTimeMillis())
        )
        // commit(), not apply(): the activity finishes immediately after this.
        prefs.edit().putString(KEY, queue.toString()).commit()
    }

    @Synchronized
    fun drain(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY, "[]"))
        val out = ArrayList<Map<String, Any>>(queue.length())
        for (i in 0 until queue.length()) {
            val o = queue.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "url" to o.optString("url"),
                    "text" to o.optString("text"),
                    "choose" to o.optBoolean("choose"),
                    "receivedAt" to o.optLong("receivedAt")
                )
            )
        }
        prefs.edit().remove(KEY).commit()
        return out
    }
}
