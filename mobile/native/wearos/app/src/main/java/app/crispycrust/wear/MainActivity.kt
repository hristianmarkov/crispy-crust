package app.crispycrust.wear

import android.app.Activity
import android.os.Bundle
import android.content.SharedPreferences
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Button
import android.view.Gravity
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import com.google.android.gms.wearable.Wearable

class MainActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private lateinit var content: LinearLayout
    private val prefs by lazy { getSharedPreferences("crispy", MODE_PRIVATE) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(24, 24, 24, 24) }
        setContentView(content)
    }
    override fun onResume() { super.onResume(); prefs.registerOnSharedPreferenceChangeListener(this); render() }
    override fun onPause() { prefs.unregisterOnSharedPreferenceChangeListener(this); super.onPause() }
    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) { runOnUiThread { render() } }
    private fun label(value: String, size: Float = 16f) { content.addView(TextView(this).apply { text = value; textSize = size; gravity = Gravity.CENTER }) }
    private fun render() {
        content.removeAllViews()
        val raw = prefs.getString("snapshot", null)
        if (raw == null) { label("Open a bake on your phone."); return }
        val task = try { JSONObject(raw) } catch (_: Exception) { label("Open phone to refresh status."); return }
        label(task.optString("title", "Bake"), 20f); label(task.optString("action"))
        label("Due: ${task.optString("dueAt")}", 14f)
        val generated = try { Instant.parse(task.getString("generatedAt")) } catch (_: Exception) { Instant.EPOCH }
        if (Instant.now().epochSecond - generated.epochSecond > 900) label("Status may be stale. Open phone.", 12f)
        content.addView(Button(this).apply { text = "Acknowledge"; setOnClickListener {
            val payload = JSONObject().put("operationId", UUID.randomUUID().toString())
                .put("bakeId", task.optString("bakeId")).put("stepId", task.optString("stepId"))
                .put("expectedRevision", task.optInt("revision")).put("type", "acknowledge")
            Wearable.getNodeClient(this@MainActivity).connectedNodes.addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) prefs.edit().putString("message", "Phone unavailable. Not acknowledged.").apply()
                else {
                    prefs.edit().putString("message", "Waiting for phone acknowledgement…").apply()
                    Wearable.getMessageClient(this@MainActivity).sendMessage(nodes.first().id,
                        "/crispy/action", payload.toString().toByteArray(Charsets.UTF_8))
                        .addOnFailureListener { prefs.edit().putString("message", "Not synced. Open phone.").apply() }
                }
            }
        } })
        label("Acknowledging does not complete the step.", 12f)
        label(prefs.getString("message", "") ?: "", 12f)
    }
}
