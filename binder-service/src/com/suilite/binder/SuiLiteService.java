package com.suilite.binder;

import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.ServiceManager;
import android.util.Log;

/**
 * SuiLiteService — Minimal Binder service for Sui-Lite verification.
 *
 * This service exists solely to:
 *   1. Prove that a custom Binder can be registered from a Magisk module
 *   2. Provide a health-check endpoint for audit scripts
 *   3. Report its own SELinux domain and UID for verification
 *
 * It does NOT perform any privileged operations, does NOT modify system
 * state, and does NOT interact with upstream system_shizuku services.
 *
 * Interface protocol (raw Parcel, no AIDL):
 *   Transaction code 1 (PING):     Returns "sui-lite-alive"
 *   Transaction code 2 (GET_INFO): Returns UID, PID, SELinux context
 */
public class SuiLiteService extends Binder {

    private static final String TAG = "SuiLiteService";

    /** Binder service name — registered with ServiceManager */
    public static final String SERVICE_NAME = "sui_lite_binder";

    /** Transaction codes (raw Parcel protocol, no AIDL) */
    private static final int TRANSACTION_PING = 1;
    private static final int TRANSACTION_GET_INFO = 2;

    @Override
    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
        switch (code) {
            case TRANSACTION_PING:
                // Health check — returns a fixed string
                reply.writeNoException();
                reply.writeString("sui-lite-alive");
                Log.i(TAG, "PING received, responded with sui-lite-alive");
                return true;

            case TRANSACTION_GET_INFO:
                // Report runtime identity for audit verification
                reply.writeNoException();
                reply.writeInt(android.os.Process.myUid());
                reply.writeInt(android.os.Process.myPid());
                reply.writeString(getSelinuxContext());
                reply.writeString(SERVICE_NAME);
                Log.i(TAG, "GET_INFO: uid=" + android.os.Process.myUid()
                        + " pid=" + android.os.Process.myPid()
                        + " ctx=" + getSelinuxContext());
                return true;

            default:
                Log.w(TAG, "Unknown transaction code: " + code);
                return super.onTransact(code, data, reply, flags);
        }
    }

    /**
     * Read this process's SELinux context from /proc/self/attr/current.
     * Returns the context string or "unknown" if unreadable.
     */
    private static String getSelinuxContext() {
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
