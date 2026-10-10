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

        val dialog = AlertDialog.Builder(this)
            .setTitle("Save to Shareby")
            .setMessage(sharedTitle?.take(140) ?: "Loading title…")
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
            // No title was shared (e.g. Instagram sends only the URL): read it from the page.
            Thread {
                val title = fetchTitle(url)
                runOnUiThread {
                    if (isFinishing || isDestroyed) return@runOnUiThread
                    if (title != null) caption = title
                    dialog.setMessage((title ?: url).take(140))
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
        raw?.let { Html.fromHtml(it, Html.FROM_HTML_MODE_LEGACY).toString().trim() }?.ifEmpty { null }
    } catch (e: Exception) {
        null
    }

    private val ogTitle = Regex(
        "<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
        RegexOption.IGNORE_CASE
    )
    private val titleTag = Regex("<title[^>]*>([^<]+)</title>", RegexOption.IGNORE_CASE)
}
