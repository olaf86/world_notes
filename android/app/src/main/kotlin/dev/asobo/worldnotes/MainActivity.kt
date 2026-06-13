package dev.asobo.worldnotes

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private lateinit var geofencingClient: GeofencingClient

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        geofencingClient = LocationServices.getGeofencingClient(this)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        geofenceEventChannel = channel
        channel.setMethodCallHandler { call, result ->
            isDartReady = true
            when (call.method) {
                "syncGeofences" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val geofences = arguments?.get("geofences") as? List<*>
                    if (geofences == null) {
                        result.error("invalid_arguments", "Missing geofences.", null)
                    } else {
                        syncGeofences(geofences, result)
                    }
                }

                "clearGeofences" -> {
                    clearGeofences { result.success(null) }
                }

                "takePendingEvents" -> {
                    result.success(takePendingEvents(this))
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        isDartReady = false
        geofenceEventChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @SuppressLint("MissingPermission")
    private fun syncGeofences(rawGeofences: List<*>, result: MethodChannel.Result) {
        if (!hasFineLocationPermission()) {
            clearGeofences {
                result.error(
                    "permission_denied",
                    "Fine and background location permission are required.",
                    null,
                )
            }
            return
        }

        val geofences = rawGeofences.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            val placeId = item["placeId"] as? String ?: return@mapNotNull null
            val latitude = item["latitude"] as? Double ?: return@mapNotNull null
            val longitude = item["longitude"] as? Double ?: return@mapNotNull null
            val radiusMeters = (item["radiusMeters"] as? Number)?.toFloat() ?: return@mapNotNull null
            if (placeId.isBlank() || radiusMeters <= 0f) return@mapNotNull null
            Geofence.Builder()
                .setRequestId(placeId)
                .setCircularRegion(latitude, longitude, radiusMeters)
                .setTransitionTypes(
                    Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT,
                )
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .build()
        }

        clearGeofences {
            if (geofences.isEmpty()) {
                result.success(null)
                return@clearGeofences
            }
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(geofences)
                .build()
            geofencingClient.addGeofences(request, geofencePendingIntent(this))
                .addOnSuccessListener {
                    val ids = geofences.map { it.requestId }.toSet()
                    getPreferences(this).edit().putStringSet(KEY_REGISTERED_IDS, ids).apply()
                    result.success(null)
                }
                .addOnFailureListener { error ->
                    result.error("geofence_add_failed", error.localizedMessage, null)
                }
        }
    }

    private fun clearGeofences(onComplete: () -> Unit) {
        val ids = getPreferences(this).getStringSet(KEY_REGISTERED_IDS, emptySet())?.toSet()
            ?: emptySet()
        if (ids.isEmpty()) {
            onComplete()
            return
        }
        geofencingClient.removeGeofences(ids.toList()).addOnCompleteListener {
            getPreferences(this).edit().remove(KEY_REGISTERED_IDS).apply()
            onComplete()
        }
    }

    private fun hasFineLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        @Volatile
        var geofenceEventChannel: MethodChannel? = null

        @Volatile
        var isDartReady: Boolean = false
    }
}

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return

        val transition = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            else -> return
        }
        val timestampMillis = System.currentTimeMillis()
        event.triggeringGeofences?.forEach { geofence ->
            val payload = mapOf(
                "placeId" to geofence.requestId,
                "transition" to transition,
                "timestampMillis" to timestampMillis,
            )
            val channel = MainActivity.geofenceEventChannel
            if (channel != null && MainActivity.isDartReady) {
                channel.invokeMethod("geofenceEvent", payload)
            } else {
                appendPendingEvent(context, payload)
            }
        }
    }
}

private const val CHANNEL_NAME = "world_notes/geofence"
private const val PREFS_NAME = "world_notes_geofences"
private const val KEY_REGISTERED_IDS = "registered_geofence_ids"
private const val KEY_PENDING_EVENTS = "pending_geofence_events"

private fun geofencePendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
    val mutabilityFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_MUTABLE
    } else {
        0
    }
    return PendingIntent.getBroadcast(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or mutabilityFlag,
    )
}

private fun getPreferences(context: Context) =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

private fun appendPendingEvent(context: Context, payload: Map<String, Any>) {
    val preferences = getPreferences(context)
    val events = JSONArray(preferences.getString(KEY_PENDING_EVENTS, "[]"))
    events.put(JSONObject(payload))
    preferences.edit().putString(KEY_PENDING_EVENTS, events.toString()).apply()
}

private fun takePendingEvents(context: Context): List<Map<String, Any>> {
    val preferences = getPreferences(context)
    val events = JSONArray(preferences.getString(KEY_PENDING_EVENTS, "[]"))
    val result = mutableListOf<Map<String, Any>>()
    for (index in 0 until events.length()) {
        val item = events.optJSONObject(index) ?: continue
        result.add(
            mapOf(
                "placeId" to item.optString("placeId"),
                "transition" to item.optString("transition"),
                "timestampMillis" to item.optLong("timestampMillis"),
            ),
        )
    }
    preferences.edit().remove(KEY_PENDING_EVENTS).apply()
    return result
}
