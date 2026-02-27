package com.suilite.binder;

import android.os.IBinder;
import android.os.Looper;
import android.os.ServiceManager;
import android.util.Log;

/**
 * BinderEntryPoint — Entry point for the Sui-Lite Binder service.
 *
 * Launched via app_process from Magisk's service.sh:
 *   /system/bin/app_process -Djava.class.path=/path/to/binder-service.jar \
 *       /system/bin com.suilite.binder.BinderEntryPoint
 *
 * Lifecycle:
 *   1. Prepare the main Looper
 *   2. Instantiate SuiLiteService (our Binder implementation)
 *   3. Register it with ServiceManager under "sui_lite_binder"
 *   4. Loop forever to keep the service alive
 *
 * This process will run as the UID/GID of whoever launched it
 * (typically root when called from Magisk service.sh).
 * SELinux context depends on the calling domain and transition rules.
 */
public class BinderEntryPoint {

    private static final String TAG = "SuiLiteBinder";

    public static void main(String[] args) {
        Log.i(TAG, "=== Sui-Lite Binder service starting ===");
        Log.i(TAG, "UID=" + android.os.Process.myUid()
                + " PID=" + android.os.Process.myPid());

        // Report SELinux context
        String ctx = readSelinuxContext();
        Log.i(TAG, "SELinux context: " + ctx);

        // Prepare looper
        Looper.prepareMainLooper();

        // Create and register service
        SuiLiteService service = new SuiLiteService();

        try {
            ServiceManager.addService(SuiLiteService.SERVICE_NAME, service);
            Log.i(TAG, "Binder service registered: " + SuiLiteService.SERVICE_NAME);
        } catch (Exception e) {
            Log.e(TAG, "Failed to register Binder service: " + e.getMessage());
            Log.e(TAG, "This is expected under SELinux Enforcing without custom policy.");
            Log.e(TAG, "Check audit/selinux/binder_contexts.txt for denial details.");

            // Do NOT exit — keep the process alive so audit scripts can
            // inspect its PID, domain, and capture denials.
            // The registration failure itself is valuable audit data.
        }

        // Log readiness
        Log.i(TAG, "Entering main loop. Service alive at PID=" + android.os.Process.myPid());

        // Keep the process alive
        Looper.loop();
    }

    private static String readSelinuxContext() {
        try {
            java.io.BufferedReader reader = new java.io.BufferedReader(
                new java.io.FileReader("/proc/self/attr/current"));
            String ctx = reader.readLine();
            reader.close();
            return ctx != null ? ctx.trim() : "unknown";
        } catch (Exception e) {
            return "unknown";
        }
    }
}
