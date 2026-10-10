package com.shareby.shareby

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

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
        val caption = listOfNotNull(subject, text).joinToString(" ").trim()
        val preview = caption.replace(url, "").trim().ifEmpty { url }.take(140)

        AlertDialog.Builder(this)
            .setTitle("Save to Shareby")
            .setMessage(preview)
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
    }
}
