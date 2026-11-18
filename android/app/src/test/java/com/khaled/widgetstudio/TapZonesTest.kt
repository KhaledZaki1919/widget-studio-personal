package com.khaled.widgetstudio

import com.khaled.widgetstudio.widget.TapZones
import org.junit.Assert.assertEquals
import org.junit.Test

/** Tap areas are absolute insets (ADR-028): the same spot whatever direction the launcher lays out in. */
class TapZonesTest {
    @Test
    fun insetsAddUpToTheWidget() {
        // A 100 × 40 px button at (20, 10) in a 200 × 100 dp widget at density 2.
        val inset = TapZones.insets(20f, 10f, 120f, 50f, 200f, 100f, 2f)
        assertEquals(10f, inset.left, 0.001f)
        assertEquals(5f, inset.top, 0.001f)
        assertEquals(140f, inset.right, 0.001f)
        assertEquals(75f, inset.bottom, 0.001f)
        assertEquals(200f, inset.left + 50f + inset.right, 0.001f)
    }

    @Test
    fun aButtonOverTheEdgeStaysInside() {
        val inset = TapZones.insets(-4f, -4f, 410f, 210f, 200f, 100f, 2f)
        assertEquals(0f, inset.left, 0.001f)
        assertEquals(0f, inset.right, 0.001f)
        assertEquals(0f, inset.bottom, 0.001f)
    }

    /** Glance drops the 11th child of a Box, which silently killed the last tiles of a big grid. */
    @Test
    fun everyButtonFitsInAGroup() {
        val groups = TapZones.groups((1..30).toList())
        assert(groups.all { it.size <= TapZones.perBox })
        assertEquals(30, groups.sumOf { it.size })
        assert(groups.size + 1 <= TapZones.perBox)
        assertEquals((1..30).toList(), groups.flatten())
    }
}
