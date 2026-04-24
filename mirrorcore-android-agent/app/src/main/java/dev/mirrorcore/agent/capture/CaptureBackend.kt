package dev.mirrorcore.agent.capture

import android.media.projection.MediaProjection
import dev.mirrorcore.agent.MirrorConfig
import dev.mirrorcore.agent.VideoSender

interface CaptureBackend {
    fun start(projection: MediaProjection, config: MirrorConfig, sender: VideoSender)
    fun stop()
}

