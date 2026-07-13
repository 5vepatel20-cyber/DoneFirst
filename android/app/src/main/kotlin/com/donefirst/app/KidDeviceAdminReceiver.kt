package com.donefirst.app

import android.app.admin.DeviceAdminReceiver

/**
 * Minimal DeviceAdminReceiver. Required so the parent app can be
 * promoted to device owner at install time via ADB:
 *
 *   adb shell dpm set-device-owner com.donefirst.app/.KidDeviceAdminReceiver
 *
 * Device-owner status is what unlocks Activity.startLockTask() on
 * the kid's device. We declare NO additional policies beyond the
 * default — the lock enforcement comes from the device-owner
 * status itself, not from any policy capability.
 *
 * This receiver is only meaningful on a device whose user has
 * flagged themselves as a kid at signup (see lib/main.dart's role
 * router). On a parent's phone it's just a dormant class.
 */
class KidDeviceAdminReceiver : DeviceAdminReceiver()