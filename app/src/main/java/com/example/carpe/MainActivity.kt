package com.example.carpe

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    CarpeDiemApp()
                }
            }
        }
    }
}

@Composable
fun CarpeDiemApp() {
    var setupDone by remember { mutableStateOf(false) }

    if (setupDone) {
        DashboardScreen()
    } else {
        PermissionsFirewallScreen(onSetupComplete = { setupDone = true })
    }
}

@Composable
fun PermissionsFirewallScreen(onSetupComplete: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Text("System Setup", style = MaterialTheme.typography.headlineLarge)
        Spacer(modifier = Modifier.height(8.dp))
        Text("Grant the following permissions and engines so Carpe Diem can ring and speak natively.", style = MaterialTheme.typography.bodyMedium)
        Spacer(modifier = Modifier.height(24.dp))
        
        Button(
            onClick = onSetupComplete,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Get Started")
        }
    }
}

data class Task(val id: String, val title: String, var isCompleted: Boolean = false)

@Composable
fun DashboardScreen() {
    val haptic = LocalHapticFeedback.current
    val toneGenerator = remember { ToneGenerator(AudioManager.STREAM_NOTIFICATION, 60) }
    
    // Cleanup ToneGenerator when screen is destroyed
    DisposableEffect(Unit) {
        onDispose { toneGenerator.release() }
    }

    var tasks by remember {
        mutableStateOf(
            listOf(
                Task("1", "Review Pull Requests"),
                Task("2", "Update Documentation"),
                Task("3", "Prepare Release Notes")
            )
        )
    }

    val playFeedback = { isDelete: Boolean ->
        // 1. Tactile Haptic Feedback
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        
        // 2. Subtle Sound Effect
        if (isDelete) {
            toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP2, 100) // Lower pitch for delete
        } else {
            toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, 100) // Higher pitch for complete
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Text("Tasks", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(16.dp))
        
        if (tasks.isEmpty()) {
            Text("All tasks completed!", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(tasks, key = { it.id }) { task ->
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = task.isCompleted,
                            onCheckedChange = { checked ->
                                // Trigger Haptic & Sound for completion toggle
                                playFeedback(false)
                                
                                tasks = tasks.map { 
                                    if (it.id == task.id) it.copy(isCompleted = checked) else it 
                                }
                            }
                        )
                        Text(
                            text = task.title,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyLarge
                        )
                        IconButton(
                            onClick = {
                                // Trigger Haptic & Sound for deletion
                                playFeedback(true)
                                tasks = tasks.filter { it.id != task.id }
                            }
                        ) {
                            Icon(
                                imageVector = Icons.Default.Delete,
                                contentDescription = "Delete Task",
                                tint = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
            }
        }
    }
}
