package app.crispycrust.wear

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

class KitchenDataService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type == DataEvent.TYPE_DELETED && event.dataItem.uri.path == "/crispy/task") {
                getSharedPreferences("crispy", MODE_PRIVATE).edit().remove("snapshot").apply()
            }
            if (event.type == DataEvent.TYPE_CHANGED && event.dataItem.uri.path == "/crispy/task") {
            val snapshot = DataMapItem.fromDataItem(event.dataItem).dataMap.getString("snapshot") ?: continue
            val valid = try { JSONObject(snapshot).getInt("schemaVersion") == 1 } catch (_: Exception) { false }
            if (valid) getSharedPreferences("crispy", MODE_PRIVATE).edit().putString("snapshot", snapshot).apply()
            }
        }
    }
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path == "/crispy/ack") {
            val accepted = try { JSONObject(String(event.data, Charsets.UTF_8)).optBoolean("accepted") } catch (_: Exception) { false }
            getSharedPreferences("crispy", MODE_PRIVATE).edit()
                .putString("message", if (accepted) "Acknowledged on phone" else "Open phone to review").apply()
        }
    }
}
