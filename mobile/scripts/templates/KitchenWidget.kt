package app.crispycrust.crispy_crust

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant

class KitchenWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val raw = context.getSharedPreferences("crispy_companion", Context.MODE_PRIVATE).getString("snapshot", null)
        val task = try { if (raw == null) null else JSONObject(raw) } catch (_: Exception) { null }
        for (id in ids) {
            val view = RemoteViews(context.packageName, android.R.layout.simple_list_item_2)
            view.setTextViewText(android.R.id.text1, task?.optString("title") ?: "Crispy Crust")
            val generated = try { Instant.parse(task?.optString("generatedAt")) } catch (_: Exception) { Instant.EPOCH }
            val stale = Instant.now().epochSecond - generated.epochSecond > 900
            view.setTextViewText(android.R.id.text2, if (task == null) "Open the app to choose a bake" else
                task.optString("action") + if (stale) " · Open app to refresh" else " · " + task.optString("dueAt"))
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW; data = Uri.parse("app.crispycrust://bakes/" + (task?.optString("bakeId") ?: ""))
            }
            val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            view.setOnClickPendingIntent(android.R.id.text1, pending)
            view.setOnClickPendingIntent(android.R.id.text2, pending)
            manager.updateAppWidget(id, view)
        }
    }
}
