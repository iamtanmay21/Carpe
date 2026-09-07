package com.local.carpe

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class QuickCaptureTileService : TileService() {

    // Called when your app can update your tile
    override fun onStartListening() {
        super.onStartListening()
        
        // Retrieve the Tile object
        val tile = qsTile ?: return
        
        tile.label = "Add Task"
        // STATE_INACTIVE means the tile is off/standby but the user can still interact with it
        tile.state = Tile.STATE_INACTIVE 
        
        // Must call updateTile() to parse the data and update the UI
        tile.updateTile()
    }

    /** Refreshes the native inline-reply notification without opening Flutter. */
    override fun onClick() {
        super.onClick()
        QuickCaptureNotification.showReady(this)
    }
}
