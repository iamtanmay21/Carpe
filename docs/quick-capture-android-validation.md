# Quick-capture Android validation matrix

The automated suite covers payload extraction, the ready → processing → ready
notification model, database WAL/busy-timeout configuration, durable request
claims, and repeated headless MethodChannel delivery. Run the instrumentation
tests on every supported API image from API 24 through the current Android
release. On Android 13 and later, run each case once with `POST_NOTIFICATIONS`
denied and once granted; the worker must still persist accepted replies when a
notification cannot be displayed.

## Device scenarios

For each API/permission combination, submit the same inline reply twice, then:

1. Swipe the app away before the work runs and verify one task is created.
2. Enable device idle/doze (`adb shell dumpsys deviceidle force-idle`), submit
   a reply, then exit idle and verify the durable work eventually completes.
3. Kill the UI process while the headless worker is running. When Android lets
   the worker continue, it must complete without UI startup; otherwise it must
   use WorkManager retry and still create at most one task.
4. Verify the primary notification action remains inline. Opening an activity
   is never an automatic fallback; any UI fallback must be an explicit user
   choice.

## MIUI manual validation

On a physical MIUI device, enable background and autostart restrictions, then
repeat the device scenarios above. Record the MIUI version, battery mode, and
whether the notification permission is granted. Confirm direct reply remains
inline when the system supports it, duplicate broadcasts do not create a
second task, and background limitations surface a retryable notification
message rather than silently launching the app.
