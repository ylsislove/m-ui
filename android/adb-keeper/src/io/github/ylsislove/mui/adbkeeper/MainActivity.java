package io.github.ylsislove.mui.adbkeeper;

import android.app.Activity;
import android.os.Bundle;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Keeper.enableAdb(this, "activity");
        BootReceiver.scheduleRetries(this);
        finish();
    }
}
