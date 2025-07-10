#!/usr/bin/env bash
# ------------------------------------------------------------------------
# setup_keepalive_ubuntu.sh – otomatisasi penuh
#  • Mempersiapkan proyek Android Studio “Firebase Keep-Alive Service”
#  • Menonaktifkan semua mode tidur/hibernate Ubuntu Desktop agar selalu ON 24 jam
# Jalankan tanpa sudo di root proyek (yang berisi folder app/) :
#     bash setup_keepalive_ubuntu.sh
# ------------------------------------------------------------------------

set -euo pipefail

# ----------- 1. Cek lingkungan ------------------------------------------------
[[ $EUID -eq 0 ]] && { echo "❌  Jalankan script ini TANPA sudo."; exit 1; }
command -v gsettings >/dev/null || { echo "❌  gsettings tidak ditemukan (GNOME Desktop dibutuhkan)."; exit 1; }

APP_DIR="app"
PKG_DIR="$APP_DIR/src/main/java/com/example/keepalive"
MANIFEST="$APP_DIR/src/main/AndroidManifest.xml"
BUILD_GRADLE="$APP_DIR/build.gradle"

[[ -f "$APP_DIR/google-services.json" ]] || { echo "❌  google-services.json belum ada di folder app/"; exit 1; }

# ----------- 2. Tambah plugin & dependensi Firebase ---------------------------
echo "⏳  Menambahkan plugin & dependensi Firebase…"
if ! grep -q "com.google.gms.google-services" "$BUILD_GRADLE"; then
  sed -i "/^plugins {/a\\    id 'com.google.gms.google-services'" "$BUILD_GRADLE"
fi
if ! grep -q "firebase-bom" "$BUILD_GRADLE"; then
  sed -i "/^dependencies {/a\\    implementation platform('com.google.firebase:firebase-bom:33.1.0')\\
    implementation 'com.google.firebase:firebase-database-ktx'" "$BUILD_GRADLE"
fi

# ----------- 3. Buat paket kode layanan --------------------------------------
echo "⏳  Menciptakan file service, receiver, application…"
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
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Firebase Keep-Alive")
            .setContentText("Menjaga koneksi Firebase 24/7")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
        startForeground(notifId, notification)

        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "\${packageName}:FirebaseKeepAlive"
        ).apply { acquire() }

        FirebaseDatabase.getInstance().setPersistenceEnabled(true)
        FirebaseDatabase.getInstance().reference.keepSynced(true)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onDestroy() { if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId,"Firebase Keep-Alive",NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
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

# ----------- 4. Patch AndroidManifest.xml ------------------------------------
echo "⏳  Memodifikasi AndroidManifest.xml…"
for P in WAKE_LOCK FOREGROUND_SERVICE RECEIVE_BOOT_COMPLETED; do
  grep -q "$P" "$MANIFEST" || sed -i "/<manifest/a\\    <uses-permission android:name=\"android.permission.$P\"/>" "$MANIFEST"
done
grep -q 'android:name=".MyApplication"' "$MANIFEST" || \
  sed -i "0,/<application /s//<application android:name=\".MyApplication\" /" "$MANIFEST"

if ! grep -q "FirebaseKeepAliveService" "$MANIFEST"; then
  sed -i "/<\/application>/i\\
        <service android:name=\".FirebaseKeepAliveService\" android:exported=\"false\" android:foregroundServiceType=\"dataSync\"/>\\
        <receiver android:name=\".BootReceiver\" android:enabled=\"true\" android:exported=\"false\">\\
            <intent-filter><action android:name=\"android.intent.action.BOOT_COMPLETED\"/></intent-filter>\\
        </receiver>" "$MANIFEST"
fi

# ----------- 5. Non-aktifkan tidur/hibernate Ubuntu Desktop -------------------
echo "⏳  Menonaktifkan semua mode tidur Ubuntu Desktop…"
# via systemd – butuh sudo
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# via GNOME power settings (AC & battery)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'

# ----------- 6. Selesai -------------------------------------------------------
echo "✅  Selesai.  • Buka Android Studio ➜ Sync Gradle ➜ Run aplikasi."
echo "💡  Ubuntu Desktop kini dikonfigurasi agar tidak pernah sleep / hibernate."
