package app.crispycrust.crispy_crust

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import org.json.JSONObject
import android.content.pm.PackageManager
import android.content.ContentUris
import android.provider.CalendarContract
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCalendar: Triple<Long, Long, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.crispycrust/kitchen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepAwake" -> {
                        if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "publishCompanion" -> {
                        val snapshot = call.argument<Map<String, Any>>("snapshot")
                        if (snapshot == null || snapshot["schemaVersion"] != 1) result.error("INVALID_SNAPSHOT", "Invalid companion task", null)
                        else {
                            getSharedPreferences("crispy_companion", MODE_PRIVATE).edit().putString("snapshot", JSONObject(snapshot).toString()).apply()
                            val manager = AppWidgetManager.getInstance(this)
                            KitchenWidget().onUpdate(this, manager, manager.getAppWidgetIds(ComponentName(this, KitchenWidget::class.java)))
                            result.success(mapOf("widget" to true, "watch" to false))
                        }
                    }
                    "readBusy" -> {
                        val start = call.argument<Number>("start")?.toLong()
                        val end = call.argument<Number>("end")?.toLong()
                        if (start == null || end == null || end <= start || end - start > 31L * 86400000) {
                            result.error("INVALID_RANGE", "Select a range of up to 31 days", null)
                        } else if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                            if (pendingCalendar != null) result.error("BUSY", "Calendar permission is already being requested", null)
                            else {
                                pendingCalendar = Triple(start, end, result)
                                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALENDAR), 1204)
                            }
                        } else readBusy(start, end, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1204) {
            val pending = pendingCalendar ?: return
            pendingCalendar = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) readBusy(pending.first, pending.second, pending.third)
            else pending.third.success(mapOf("status" to "denied"))
        }
    }
    private fun readBusy(start: Long, end: Long, result: MethodChannel.Result) {
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)
        val blocks = mutableListOf<Map<String, Long>>()
        try {
            // Only time columns leave the native calendar layer. No title, attendee or location query.
            contentResolver.query(builder.build(), arrayOf(CalendarContract.Instances.BEGIN, CalendarContract.Instances.END),
                "${CalendarContract.Instances.AVAILABILITY} != ?", arrayOf(CalendarContract.Events.AVAILABILITY_FREE.toString()), null)?.use { cursor ->
                while (cursor.moveToNext()) blocks.add(mapOf("start" to cursor.getLong(0), "end" to cursor.getLong(1)))
            }
            result.success(mapOf("status" to "available", "blocks" to blocks))
        } catch (_: SecurityException) { result.success(mapOf("status" to "denied")) }
    }
}
