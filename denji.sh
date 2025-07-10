#!/usr/bin/env bash
# ------------------------------------------------------------------------
# setup_keepalive_ubuntu_root.sh
# Otomatisasi penuh:
#   • Menyiapkan layanan “Firebase Keep-Alive” di proyek Android Studio
#   • Menonaktifkan semua mode sleep/hibernate Ubuntu Desktop
#
# Jalankan di root folder proyek Android Studio (yang memiliki folder ‘app/’):
#     sudo bash setup_keepalive_ubuntu_root.sh
# ------------------------------------------------------------------------

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "❌  Jalankan script menggunakan sudo."; exit 1; }

PROJECT_USER=${SUDO_USER:-$(logname)}
APP_DIR="app"
PKG_DIR="$APP_DIR/src/main/java/com/example/keepalive"
MANIFEST="$APP_DIR/src/main/AndroidManifest.xml"
BUILD_GRADLE="$APP_DIR/build.gradle"

[[ -d "$APP_DIR" ]]       || { echo "❌  Folder 'app/' tidak ditemukan."; exit 1; }
[[ -f "$APP_DIR/google-services.json" ]] \
                          || { echo "❌  google-services.json belum ada di folder app/"; exit 1; }

echo "⏳  Menambahkan plugin & dependensi Firebase…"
grep -q "com.google.gms.google-services" "$BUILD_GRADLE" || \
  sed -i "/^plugins {/a\\    id 'com.google.gms.google-services'" "$BUILD_GRADLE"

grep -q "firebase-bom" "$BUILD_GRADLE" || \
  sed -i "/^dependencies {/a\\    implementation platform('com.google.firebase:firebase-bom:33.1.0')\\
    implementation 'com.google.firebase:firebase-database-ktx'" "$BUILD_GRADLE"

echo "⏳  Membuat paket $PKG_DIR…"
mkdir -p "$PKG_DIR"

cat > "$PKG_DIR/FirebaseKeepAliveService.kt" <<'EOF'
package com.example.keepalive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.google.firebase.database.FirebaseDatabase

class FirebaseKeepAliveService : Service() {
    private lateinit var wakeLock: PowerManager.WakeLock
    private val channelId = "firebase_keep_alive"
    private val notifId = 1
    override fun onCreate() {
        super.onCreate()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId,"Firebase Keep-Alive",NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Firebase Keep-Alive")
            .setContentText("Menjaga koneksi Firebase 24/7")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true).build()
        startForeground(notifId, notif)

        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
            "\${packageName}:FirebaseKeepAlive").apply { acquire() }

        FirebaseDatabase.getInstance().setPersistenceEnabled(true)
        FirebaseDatabase.getInstance().reference.keepSynced(true)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY
    override fun onDestroy() { if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release(); super.onDestroy() }
    override fun onBind(intent: Intent?) : IBinder? = null
}
EOF

cat > "$PKG_DIR/BootReceiver.kt" <<'EOF'
package com.example.keepalive
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            context.startForegroundService(Intent(context, FirebaseKeepAliveService::class.java))
        }
    }
}
EOF

cat > "$PKG_DIR/MyApplication.kt" <<'EOF'
package com.example.keepalive
import android.app.Application
import android.content.Intent

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startService(Intent(this, FirebaseKeepAliveService::class.java))
    }
}
EOF

echo "⏳  Memodifikasi AndroidManifest.xml…"
for P in WAKE_LOCK FOREGROUND_SERVICE RECEIVE_BOOT_COMPLETED; do
    grep -q "$P" "$MANIFEST" || \
      sed -i "/<manifest/a\\    <uses-permission android:name=\"android.permission.$P\"/>" "$MANIFEST"
done
grep -q 'android:name=".MyApplication"' "$MANIFEST" || \
  sed -i "0,/<application /s//<application android:name=\".MyApplication\" /" "$MANIFEST"

grep -q "FirebaseKeepAliveService" "$MANIFEST" || \
  sed -i "/<\/application>/i\\
        <service android:name=\".FirebaseKeepAliveService\" android:exported=\"false\" android:foregroundServiceType=\"dataSync\"/>\\
        <receiver android:name=\".BootReceiver\" android:enabled=\"true\" android:exported=\"false\">\\
            <intent-filter><action android:name=\"android.intent.action.BOOT_COMPLETED\"/></intent-filter>\\
        </receiver>" "$MANIFEST"

echo "⏳  Menonaktifkan mode sleep/hibernate Ubuntu Desktop…"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo -u "$PROJECT_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
sudo -u "$PROJECT_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
sudo -u "$PROJECT_USER" gsettings set org.gnome.desktop.session idle-delay 0
sudo -u "$PROJECT_USER" gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
sudo -u "$PROJECT_USER" gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'

echo "✅  Selesai.  Sinkronkan Gradle di Android Studio lalu jalankan aplikasi untuk mengaktifkan layanan Firebase Keep-Alive."
