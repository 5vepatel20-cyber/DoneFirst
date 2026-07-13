package com.donefirst.app

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
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