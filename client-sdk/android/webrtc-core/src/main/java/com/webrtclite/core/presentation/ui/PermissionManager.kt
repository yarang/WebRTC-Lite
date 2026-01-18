package com.webrtclite.core.presentation.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for handling runtime permissions
 */
@Singleton
class PermissionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    /**
     * Check if all required permissions are granted
     */
    fun hasAllPermissions(): Boolean {
        return REQUIRED_PERMISSIONS.all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Check if specific permission is granted
     */
    fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Get missing permissions
     */
    fun getMissingPermissions(): Array<String> {
        return REQUIRED_PERMISSIONS.filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()
    }

    companion object {
        val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.MODIFY_AUDIO_SETTINGS
        )

        val OPTIONAL_PERMISSIONS = arrayOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_CONNECT
        )
    }
}

/**
 * Permission launcher for ComponentActivity
 */
class PermissionLauncher(
    private val activity: ComponentActivity,
    private val onAllGranted: () -> Unit,
    private val onDenied: (List<String>) -> Unit
) {
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val denied = permissions.filterValues { !it }.keys.toList()
        if (denied.isEmpty()) {
            onAllGranted()
        } else {
            onDenied(denied)
        }
    }

    /**
     * Launch permission request
     */
    fun launchPermissions() {
        val missing = PermissionManager(activity).getMissingPermissions()
        if (missing.isEmpty()) {
            onAllGranted()
        } else {
            launcher.launch(missing)
        }
    }

    /**
     * Launch specific permissions
     */
    fun launch(permissions: Array<String>) {
        launcher.launch(permissions)
    }
}
