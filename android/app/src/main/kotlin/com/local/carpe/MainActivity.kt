package com.local.carpe

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register as soon as the user opens the app so Android surfaces Carpe
        // in Calling Accounts before the first alarm or incoming call.
        CallManager.registerAccount(this)
    }
}
