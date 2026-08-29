package com.local.carpe

import android.content.Intent
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

    // Called when the user taps on your tile
    override fun onClick() {
        super.onClick()
        
        val intent = Intent(this, MainActivity::class.java).apply {
            // Starting with Android API 28, this flag is required to launch from a Tile
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("OPEN_CAPTURE_SHEET", true)
        }
        
        // Starts the activity while collapsing the Quick Settings panel
        startActivityAndCollapse(intent)
    }
}
