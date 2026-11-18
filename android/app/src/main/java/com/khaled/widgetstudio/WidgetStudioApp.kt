package com.khaled.widgetstudio

import android.app.Application
import com.khaled.widgetstudio.spec.Capabilities

/** Loads the capability catalog before any receiver, screen or validator needs it (ADR-027). */
class WidgetStudioApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Capabilities.load(assets)
    }
}
