package dev.mirrorcore.agent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private val mediaProjectionManager by lazy {
        getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode != RESULT_OK || result.data == null) {
            return@registerForActivityResult
        }

        val config = MirrorConfig.fromUi(
            findViewById(R.id.scale_spinner),
            findViewById(R.id.fps_spinner),
            findViewById(R.id.bitrate_spinner),
        )

        val intent = Intent(this, MirrorService::class.java).apply {
            action = MirrorService.ACTION_START
            putExtra(MirrorService.EXTRA_RESULT_CODE, result.resultCode)
            putExtra(MirrorService.EXTRA_RESULT_DATA, result.data)
            putExtra(MirrorService.EXTRA_CONFIG, config)
        }
        ContextCompat.startForegroundService(this, intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        setupSpinners()
        maybeRequestNotificationsPermission()

        findViewById<Button>(R.id.start_button).setOnClickListener {
            captureLauncher.launch(mediaProjectionManager.createScreenCaptureIntent())
        }

        findViewById<Button>(R.id.stop_button).setOnClickListener {
            val intent = Intent(this, MirrorService::class.java).apply {
                action = MirrorService.ACTION_STOP
            }
            startService(intent)
        }

        if (intent.getBooleanExtra(EXTRA_AUTOSTART, false)) {
            captureLauncher.launch(mediaProjectionManager.createScreenCaptureIntent())
        }
    }

    private fun setupSpinners() {
        val scale = findViewById<Spinner>(R.id.scale_spinner)
        scale.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            listOf("1.0", "0.75", "0.5"),
        )
        scale.setSelection(0)

        val fps = findViewById<Spinner>(R.id.fps_spinner)
        fps.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            listOf("60", "30"),
        )
        fps.setSelection(0)

        val bitrate = findViewById<Spinner>(R.id.bitrate_spinner)
        bitrate.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            listOf("Auto", "16Mbps", "8Mbps"),
        )
        bitrate.setSelection(0)
    }

    private fun maybeRequestNotificationsPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    companion object {
        const val EXTRA_AUTOSTART = "autostart"
    }
}
