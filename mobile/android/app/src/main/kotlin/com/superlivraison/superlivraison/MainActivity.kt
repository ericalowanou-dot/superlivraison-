package com.superlivraison.superlivraison

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Canal prioritaire : la notification s'affiche en bandeau en haut de l'écran,
    // avec son et vibration, comme une messagerie. Le nom est celui que l'utilisateur
    // voit dans les réglages de notifications du téléphone.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Messages et courses",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Nouveaux messages et suivi de vos courses"
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        // Doit correspondre au canal envoyé par le serveur et à celui du manifeste.
        const val CHANNEL_ID = "superlivraison"
    }
}
