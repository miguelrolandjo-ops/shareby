package com.shareby.shareby

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.text.Html
import android.widget.Toast
import java.net.HttpURLConnection
import java.net.URL

/**
 * Receives ACTION_SEND text from other apps' share sheet.
 *
 * Shows a small native dialog over the source app:
 *   Save              -> queue it, toast, back to the source app (sorted later in Shareby)
 *   Choose collection -> queue it and open Shareby, which shows the collection picker
 *   Cancel            -> nothing saved
 */
class ShareReceiverActivity : Activity() {

    private val urlPattern = Regex("https?://[^\\s<>\"]+", RegexOption.IGNORE_CASE)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
        val url = text?.let { urlPattern.find(it)?.value?.trimEnd('.', ',', ')', '!', '?', ';', ':') }
        if (url.isNullOrEmpty()) {
            Toast.makeText(applicationContext, "Shareby can only save links", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        val subject = intent?.getStringExtra(Intent.EXTRA_SUBJECT)
        var caption = listOfNotNull(subject, text).joinToString(" ").trim()
        // The title the source app shared with the link (YouTube etc.), if any.
        val sharedTitle = (subject ?: text.replace(url, "")).trim().ifEmpty { null }

        // Buttons always act immediately. If the page title has already arrived it is saved
        // with the link; if not, the app looks the title up itself once it has the link.
        val dialog = AlertDialog.Builder(this)
            .setTitle("Save to Shareby")
            .setMessage(sharedTitle?.take(140) ?: url.take(140))
            .setPositiveButton("Save") { _, _ ->
                ShareInbox.add(applicationContext, url, caption, choose = false)
                Toast.makeText(applicationContext, "Saved to Shareby. We'll sort it for you", Toast.LENGTH_SHORT).show()
                finish()
            }
            .setNeutralButton("Choose collection") { _, _ ->
                ShareInbox.add(applicationContext, url, caption, choose = true)
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                finish()
            }
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()

        if (sharedTitle == null) {
            // No title was shared (e.g. Instagram sends only the URL): try to show one here.
            Thread {
                val title = fetchTitle(url)
                runOnUiThread {
                    if (isFinishing || isDestroyed || title == null) return@runOnUiThread
                    caption = title
                    dialog.setMessage(title.take(140))
                }
            }.start()
        }
    }

    /** Best-effort page title (og:title, then <title>). Returns null on any failure. */
    private fun fetchTitle(url: String): String? = try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 4000
            readTimeout = 4000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) Shareby")
        }
        // Titles live in <head>; the first 64 KB is plenty.
        val html = conn.inputStream.use { input ->
            val buf = ByteArray(64 * 1024)
            var n = 0
            while (n < buf.size) {
                val r = input.read(buf, n, buf.size - n)
                if (r < 0) break
                n += r
            }
            String(buf, 0, n, Charsets.UTF_8)
        }
        val raw = ogTitle.find(html)?.groupValues?.get(1) ?: titleTag.find(html)?.groupValues?.get(1)
        raw?.let { Html.fromHtml(it, Html.FROM_HTML_MODE_LEGACY).toString().trim() }
            ?.takeIf { it.isNotEmpty() && !isGenericTitle(it) }
    } catch (e: Exception) {
        null
    }

    /** Login walls and site names say nothing about the link itself. */
    private fun isGenericTitle(t: String): Boolean {
        val l = t.lowercase()
        return l == "instagram" || l == "tiktok" || l == "youtube" || l.startsWith("login") ||
            l.startsWith("log in") || l.contains("make your day") || l.contains("• instagram photos and videos")
    }

    private val ogTitle = Regex(
        "<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
        RegexOption.IGNORE_CASE
    )
    private val titleTag = Regex("<title[^>]*>([^<]+)</title>", RegexOption.IGNORE_CASE)
}
