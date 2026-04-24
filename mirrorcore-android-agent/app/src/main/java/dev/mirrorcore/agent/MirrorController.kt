package dev.mirrorcore.agent

import android.content.Context
import android.media.projection.MediaProjection

class MirrorController(
    private val applicationContext: Context,
    private val projection: MediaProjection,
    private val config: MirrorConfig,
) {
    fun start() {
        // Phase 2: implemented in subsequent commits (sockets + capture backend).
    }

    fun stop() {
        // Phase 2: implemented in subsequent commits.
    }
}

