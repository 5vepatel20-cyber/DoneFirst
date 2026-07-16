package com.donefirst.app

import android.app.Activity
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter's KioskService (kid-side only) to Android's
 * lock-task API.
 *
 * The "donefirst/kiosk" MethodChannel exposes three methods:
 *
 *   • startLockTask()  — calls Activity.startLockTask(). The OS only
 *     honours this if our package is the device owner (set up via
 *     `adb shell dpm set-device-owner com.donefirst.app/.KidDeviceAdminReceiver`
 *     at install time, per SETUP.md). If we are NOT the device owner,
 *     we silently no-op and rely on flutter_screentime's app-block
 *     enforcement alone — the kid can still launch other apps, but
 *     the AccessibilityService bounces them straight back. Better
 *     than crashing the kid into a black screen with no UI.
 *
 *   • stopLockTask() — symmetric to start. Also a no-op if we
 *     aren't the device owner.
 *
 *   • isDeviceOwner() — reports back to Dart so the UI can show
 *     "Set up lock-task: see SETUP.md" when the kid installs the
 *     app on a device that hasn't been ADB-promoted yet.
 *
 * On a parent's phone, none of this is ever called — the parent
 * UI never invokes KioskService. The receiver and MethodChannel
 * are present unconditionally so a single APK supports both roles.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "donefirst/kiosk"
    private val PERMISSIONS_CHANNEL = "donefirst/permissions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> {
                    try {
                        if (isDeviceOwner()) {
                            startLockTask()
                            result.success(true)
                        } else {
                            // Not the device owner — silently skip.
                            // flutter_screentime's app-level block is
                            // still in force; this kid just won't get
                            // the OS-level launcher lock.
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        // startLockTask throws IllegalStateException on
                        // some OEMs if called twice in quick succession;
                        // bubble a clean error string back to Dart.
                        result.error(
                            "LOCK_TASK_FAILED",
                            e.message ?: "startLockTask threw",
                            null,
                        )
                    }
                }
                "stopLockTask" -> {
                    try {
                        // We could check isInLockTaskMode first, but
                        // FlutterActivity's superclass chain doesn't
                        // surface the API-23 method on the Kotlin
                        // side at compile time. Just call stopLockTask
                        // and let it throw if we're not in lock task
                        // mode — the catch handles that case.
                        if (isDeviceOwner()) {
                            stopLockTask()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "STOP_LOCK_TASK_FAILED",
                            e.message ?: "stopLockTask threw",
                            null,
                        )
                    }
                }
                "isDeviceOwner" -> result.success(isDeviceOwner())
                else -> result.notImplemented()
            }
        }

        // Per-permission status + grant-flow helpers for the
        // DevicePermissionsScreen. flutter_screentime's combined
        // checkAuthorization() can't tell us WHICH of the two
        // required Android permissions (usage-stats, overlay) is
        // missing — we need to check each individually so the UI
        // can show a separate row per permission.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsageAccess" -> {
                    // AppOpsManager.OPSTR_GET_USAGE_STATS is the
                    // canonical "Usage Access" toggle. The package
                    // itself can check via AppOpsManager; Settings
                    // doesn't expose a public helper.
                    val mode = (getSystemService(Context.APP_OPS_SERVICE)
                        as? AppOpsManager)?.unsafeCheckOpNoThrow(
                        AppOpsManager.OPSTR_GET_USAGE_STATS,
                        Process.myUid(),
                        packageName,
                    )
                    // MODE_ALLOWED == 0; everything else is denied.
                    result.success(mode == AppOpsManager.MODE_ALLOWED)
                }
                "checkOverlay" -> {
                    // canDrawOverlays is API-23+. Same minSdk as the
                    // app, so unconditional; Build.VERSION check
                    // kept for forward-portability (matches the
                    // isDeviceOwner pattern above).
                    val granted = if (Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.M
                    ) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "openUsageAccessSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        // Some OEM ROMs (MIUI historically) ship
                        // without the usage-access settings activity;
                        // fall back to the app details page so the
                        // user can still find the toggle.
                        result.error(
                            "NO_USAGE_SETTINGS",
                            e.message ?: "Usage access settings unavailable",
                            null,
                        )
                    }
                }
                "openOverlaySettings" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "NO_OVERLAY_SETTINGS",
                            e.message ?: "Overlay settings unavailable",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isDeviceOwner(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE)
                as? DevicePolicyManager ?: return false
        // isDeviceOwnerApp requires API 23+; we set minSdk=23 so this
        // is unconditional. Keeping the Build.VERSION check anyway
        // for forward-portability — if a future flutter bump changes
        // the default minSdk, we don't want a silent crash here.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            dpm.isDeviceOwnerApp(packageName)
        } else {
            false
        }
    }

    companion object {
        // Component name used by the SETUP.md docs when calling
        // `adb shell dpm set-device-owner <component>`.
        @JvmStatic
        fun adminComponentName(ctx: Context): ComponentName =
            ComponentName(ctx, KidDeviceAdminReceiver::class.java)
    }
}