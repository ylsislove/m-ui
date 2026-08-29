package io.github.ylsislove.mui.adbkeeper;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;
import android.util.Log;

public final class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "MuiAdbKeeper";
    private static final long[] RETRY_DELAYS_MS = {10_000L, 30_000L, 90_000L};

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? "unknown" : intent.getAction();
        Keeper.enableAdb(context, action);
        scheduleRetries(context);
    }

    static void scheduleRetries(Context context) {
        AlarmManager alarmManager = context.getSystemService(AlarmManager.class);
        if (alarmManager == null) {
            Log.e(TAG, "AlarmManager is unavailable");
            return;
        }

        for (int index = 0; index < RETRY_DELAYS_MS.length; index++) {
            Intent retryIntent = new Intent(context, RetryReceiver.class)
                    .setAction(context.getPackageName() + ".RETRY_" + index);
            PendingIntent pendingIntent = PendingIntent.getBroadcast(
                    context,
                    index,
                    retryIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + RETRY_DELAYS_MS[index],
                    pendingIntent);
        }
    }
}
