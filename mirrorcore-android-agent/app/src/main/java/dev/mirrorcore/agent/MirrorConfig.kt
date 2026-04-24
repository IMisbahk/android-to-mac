package dev.mirrorcore.agent

import android.os.Parcelable
import android.widget.Spinner
import kotlinx.parcelize.Parcelize

@Parcelize
data class MirrorConfig(
    val scale: Float,
    val fps: Int,
    val bitratebps: Int,
) : Parcelable {
    companion object {
        fun fromUi(scaleSpinner: Spinner, fpsSpinner: Spinner, bitrateSpinner: Spinner): MirrorConfig {
            val scale = scaleSpinner.selectedItem.toString().toFloat()
            val fps = fpsSpinner.selectedItem.toString().toInt()
            val bitratebps = when (bitrateSpinner.selectedItem.toString()) {
                "8Mbps" -> 8_000_000
                "16Mbps" -> 16_000_000
                else -> 0
            }
            return MirrorConfig(scale = scale, fps = fps, bitratebps = bitratebps)
        }
    }
}

