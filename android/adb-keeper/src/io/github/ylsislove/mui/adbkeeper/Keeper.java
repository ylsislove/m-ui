package io.github.ylsislove.mui.adbkeeper;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.util.Log;

final class Keeper {
    private static final String TAG = "MuiAdbKeeper";

    private Keeper() {
    }

    static boolean hasPermission(Context context) {
        return context.getPackageManager().checkPermission(
                Manifest.permission.WRITE_SECURE_SETTINGS,
                context.getPackageName()) == PackageManager.PERMISSION_GRANTED;
    }

    static boolean enableAdb(Context context, String reason) {
        if (!hasPermission(context)) {
            Log.e(TAG, "WRITE_SECURE_SETTINGS is not granted; reason=" + reason);
            return false;
        }

        try {
            boolean developmentUpdated = Settings.Global.putInt(
                    context.getContentResolver(),
                    Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                    1);
            boolean adbUpdated = Settings.Global.putInt(
                    context.getContentResolver(),
                    Settings.Global.ADB_ENABLED,
                    1);
            Log.i(TAG, "ADB enable requested; reason=" + reason
                    + ", developmentUpdated=" + developmentUpdated
                    + ", adbUpdated=" + adbUpdated);
            return developmentUpdated && adbUpdated;
        } catch (RuntimeException error) {
            Log.e(TAG, "Unable to enable ADB; reason=" + reason, error);
            return false;
        }
    }
}
