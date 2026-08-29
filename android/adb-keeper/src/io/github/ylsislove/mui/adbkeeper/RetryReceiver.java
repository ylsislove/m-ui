package io.github.ylsislove.mui.adbkeeper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class RetryReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? "retry" : intent.getAction();
        Keeper.enableAdb(context, action);
    }
}
