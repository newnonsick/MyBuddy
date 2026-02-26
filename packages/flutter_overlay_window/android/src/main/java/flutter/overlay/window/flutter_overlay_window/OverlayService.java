package flutter.overlay.window.flutter_overlay_window;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.app.PendingIntent;
import android.graphics.Point;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;
import io.flutter.plugin.common.MethodChannel;

public class OverlayService extends Service implements View.OnTouchListener {
    private final int DEFAULT_NAV_BAR_HEIGHT_DP = 48;
    private final int DEFAULT_STATUS_BAR_HEIGHT_DP = 25;

    private Integer mStatusBarHeight = -1;
    private Integer mNavigationBarHeight = -1;
    private Resources mResources;

    public static final String INTENT_EXTRA_IS_CLOSE_WINDOW = "IsCloseWindow";

    private static OverlayService instance;
    public static boolean isRunning = false;
    private WindowManager windowManager = null;
    private FlutterView flutterView;
    private MethodChannel flutterChannel;
    private BasicMessageChannel<Object> overlayMessageChannel;
    private int clickableFlag = WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;

    private Handler mAnimationHandler = new Handler();
    private float lastX, lastY;
    private int lastYPosition;
    private boolean dragging;
    private static final float MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER = 0.8f;
    private Point szWindow = new Point();
    private Timer mTrayAnimationTimer;
    private TrayAnimationTimerTask mTrayTimerTask;

    private android.widget.FrameLayout trashView;
    private WindowManager.LayoutParams trashParams;
    private boolean isTrashVisible = false;
    private boolean overTrash = false;

    // --- Messenger-style trash snap, vibration & magnetic pull ---
    private static final int VIBRATION_DURATION_MS = 20;
    private static final float TRASH_DAMPING_MIN = 0.15f;
    private static final float TRASH_ACTIVE_SCALE = 1.3f;
    private boolean hasVibratedForTrash = false;
    private Vibrator vibrator;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverLay", "Destroying the overlay window service");
        if (trashView != null && windowManager != null) {
            trashView.animate().cancel();
            try {
                windowManager.removeView(trashView);
            } catch (IllegalArgumentException e) {
                Log.w("OverLay", "trashView was not attached to window manager");
            }
            trashView = null;
        }
        if (windowManager != null) {
            windowManager.removeView(flutterView);
            windowManager = null;
            flutterView.detachFromFlutterEngine();
            flutterView = null;
        }
        isRunning = false;
        NotificationManager notificationManager = (NotificationManager) getApplicationContext()
                .getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.cancel(OverlayConstants.NOTIFICATION_ID);
        instance = null;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        mResources = getApplicationContext().getResources();
        int startX = intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
        int startY = intent.getIntExtra("startY", OverlayConstants.DEFAULT_XY);
        boolean isCloseWindow = intent.getBooleanExtra(INTENT_EXTRA_IS_CLOSE_WINDOW, false);
        if (isCloseWindow) {
            if (windowManager != null && flutterView != null) {
                windowManager.removeView(flutterView);
                windowManager = null;
                flutterView.detachFromFlutterEngine();
                stopSelf();
            }
            isRunning = false;
            return START_STICKY;
        }
        if (windowManager != null && flutterView != null) {
            windowManager.removeView(flutterView);
            windowManager = null;
            flutterView.detachFromFlutterEngine();
            stopSelf();
        }
        isRunning = true;
        Log.d("onStartCommand", "Service started");
        FlutterEngine engine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);
        engine.getLifecycleChannel().appIsResumed();
        flutterView = new FlutterView(getApplicationContext(), new FlutterTextureView(getApplicationContext()));
        flutterView.attachToFlutterEngine(FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG));
        flutterView.setFitsSystemWindows(true);
        flutterView.setFocusable(true);
        flutterView.setFocusableInTouchMode(true);
        flutterView.setBackgroundColor(Color.TRANSPARENT);
        flutterChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("updateFlag")) {
                String flag = call.argument("flag").toString();
                updateOverlayFlag(result, flag);
            } else if (call.method.equals("updateOverlayPosition")) {
                int x = call.<Integer>argument("x");
                int y = call.<Integer>argument("y");
                moveOverlay(x, y, result);
            } else if (call.method.equals("resizeOverlay")) {
                int width = call.argument("width");
                int height = call.argument("height");
                boolean enableDrag = call.argument("enableDrag");
                resizeOverlay(width, height, enableDrag, result);
            }
        });
        overlayMessageChannel.setMessageHandler((message, reply) -> {
            Log.d("OverlayIPC", "overlay→main handler fired, message="
                    + (message != null ? message.getClass().getSimpleName() : "null"));
            if (WindowSetup.messenger == null) {
                Log.e("OverlayIPC", "WindowSetup.messenger is NULL — cannot forward to main engine");
                reply.reply(null);
                return;
            }
            try {
                WindowSetup.messenger.send(message);
                Log.d("OverlayIPC", "forwarded to main engine OK");
            } catch (Exception e) {
                Log.e("OverlayIPC", "send to main engine FAILED: " + e.getMessage(), e);
            }
            reply.reply(null);
        });
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            windowManager.getDefaultDisplay().getSize(szWindow);
        } else {
            DisplayMetrics displaymetrics = new DisplayMetrics();
            windowManager.getDefaultDisplay().getMetrics(displaymetrics);
            int w = displaymetrics.widthPixels;
            int h = displaymetrics.heightPixels;
            szWindow.set(w, h);
        }
        int dx = startX == OverlayConstants.DEFAULT_XY ? 0 : startX;
        int dy = startY == OverlayConstants.DEFAULT_XY ? -statusBarHeightPx() : startY;
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowSetup.width == -1999 ? -1 : WindowSetup.width,
                WindowSetup.height != -1999 ? WindowSetup.height : screenHeight(),
                0,
                -statusBarHeightPx(),
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                        : WindowManager.LayoutParams.TYPE_PHONE,
                WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
                        | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
            params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
        }
        params.gravity = WindowSetup.gravity;
        flutterView.setOnTouchListener(this);
        windowManager.addView(flutterView, params);
        moveOverlay(dx, dy, null);
        initTrashView();
        return START_STICKY;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    private int screenHeight() {
        Display display = windowManager.getDefaultDisplay();
        DisplayMetrics dm = new DisplayMetrics();
        display.getRealMetrics(dm);
        return inPortrait() ? dm.heightPixels + statusBarHeightPx() + navigationBarHeightPx()
                : dm.heightPixels + statusBarHeightPx();
    }

    private int statusBarHeightPx() {
        if (mStatusBarHeight == -1) {
            int statusBarHeightId = mResources.getIdentifier("status_bar_height", "dimen", "android");

            if (statusBarHeightId > 0) {
                mStatusBarHeight = mResources.getDimensionPixelSize(statusBarHeightId);
            } else {
                mStatusBarHeight = dpToPx(DEFAULT_STATUS_BAR_HEIGHT_DP);
            }
        }

        return mStatusBarHeight;
    }

    int navigationBarHeightPx() {
        if (mNavigationBarHeight == -1) {
            int navBarHeightId = mResources.getIdentifier("navigation_bar_height", "dimen", "android");

            if (navBarHeightId > 0) {
                mNavigationBarHeight = mResources.getDimensionPixelSize(navBarHeightId);
            } else {
                mNavigationBarHeight = dpToPx(DEFAULT_NAV_BAR_HEIGHT_DP);
            }
        }

        return mNavigationBarHeight;
    }

    private void updateOverlayFlag(MethodChannel.Result result, String flag) {
        if (windowManager != null) {
            WindowSetup.setFlag(flag);
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.flags = WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS |
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
                    | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
                params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
            } else {
                params.alpha = 1;
            }
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void cancelTrayAnimation() {
        if (mTrayTimerTask != null) {
            mTrayTimerTask.cancel();
            mTrayTimerTask = null;
        }
        if (mTrayAnimationTimer != null) {
            mTrayAnimationTimer.cancel();
            mTrayAnimationTimer = null;
        }
        // Remove any already-posted Runnables from the Handler queue.
        // Without this, a Runnable posted by TrayAnimationTimerTask.run()
        // just before cancel() can still execute and cause NPE or stale
        // position updates.
        mAnimationHandler.removeCallbacksAndMessages(null);
    }

    private void resizeOverlay(int width, int height, boolean enableDrag, MethodChannel.Result result) {
        if (windowManager != null) {
            cancelTrayAnimation();
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.width = (width == -1999 || width == -1) ? -1 : dpToPx(width);
            params.height = (height != 1999 || height != -1) ? dpToPx(height) : height;
            WindowSetup.enableDrag = enableDrag;
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void moveOverlay(int x, int y, MethodChannel.Result result) {
        if (windowManager != null) {
            cancelTrayAnimation();
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.x = (x == -1999 || x == -1) ? -1 : dpToPx(x);
            params.y = dpToPx(y);
            windowManager.updateViewLayout(flutterView, params);
            if (result != null)
                result.success(true);
        } else {
            if (result != null)
                result.success(false);
        }
    }

    public static Map<String, Double> getCurrentPosition() {
        if (instance != null && instance.flutterView != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
            Map<String, Double> position = new HashMap<>();
            position.put("x", instance.pxToDp(params.x));
            position.put("y", instance.pxToDp(params.y));
            return position;
        }
        return null;
    }

    public static boolean moveOverlay(int x, int y) {
        if (instance != null && instance.flutterView != null) {
            if (instance.windowManager != null) {
                instance.cancelTrayAnimation();
                WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
                params.x = (x == -1999 || x == -1) ? -1 : instance.dpToPx(x);
                params.y = instance.dpToPx(y);
                instance.windowManager.updateViewLayout(instance.flutterView, params);
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    @Override
    public void onCreate() {
        mResources = getApplicationContext().getResources();
        // Get the cached FlutterEngine
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);

        if (flutterEngine == null) {
            // Handle the error if engine is not found
            Log.e("OverlayService", "Flutter engine not found, hence creating new flutter engine");
            FlutterEngineGroup engineGroup = new FlutterEngineGroup(this);
            DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "overlayMain"); // "overlayMain" is custom entry point

            flutterEngine = engineGroup.createAndRunEngine(this, entryPoint);

            // Cache the created FlutterEngine for future use
            FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, flutterEngine);
        }

        // Create the MethodChannel with the properly initialized FlutterEngine
        if (flutterEngine != null) {
            flutterChannel = new MethodChannel(flutterEngine.getDartExecutor(), OverlayConstants.OVERLAY_TAG);
            overlayMessageChannel = new BasicMessageChannel(flutterEngine.getDartExecutor(),
                    OverlayConstants.MESSENGER_TAG, JSONMessageCodec.INSTANCE);
        }

        createNotificationChannel();
        Intent notificationIntent = new Intent(this, FlutterOverlayWindowPlugin.class);
        int pendingFlags;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            pendingFlags = PendingIntent.FLAG_IMMUTABLE;
        } else {
            pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(this,
                0, notificationIntent, pendingFlags);
        final int notifyIcon = getDrawableResourceId("mipmap", "launcher");
        Notification notification = new NotificationCompat.Builder(this, OverlayConstants.CHANNEL_ID)
                .setContentTitle(WindowSetup.overlayTitle)
                .setContentText(WindowSetup.overlayContent)
                .setSmallIcon(notifyIcon == 0 ? R.drawable.notification_icon : notifyIcon)
                .setContentIntent(pendingIntent)
                .setVisibility(WindowSetup.notificationVisibility)
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                            | android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        } else {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        }
        vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        instance = this;
    }

    private void sendCloseToFlutter() {
        if (overlayMessageChannel != null) {
            overlayMessageChannel.send("{\"type\":\"close_overlay\"}");
        }
    }

    private void initTrashView() {
        if (trashView != null && trashView.isAttachedToWindow()) {
            return; // already initialized
        }
        trashView = new android.widget.FrameLayout(this);
        trashView.setVisibility(View.GONE);
        
        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
        bg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        bg.setColor(Color.parseColor("#99161618")); 
        bg.setStroke(dpToPx(1), Color.parseColor("#44FFFFFF"));
        trashView.setBackground(bg);
        
        android.widget.TextView textView = new android.widget.TextView(this);
        textView.setText("✕");
        textView.setTextColor(Color.WHITE);
        textView.setTextSize(24);
        textView.setGravity(Gravity.CENTER);
        android.widget.FrameLayout.LayoutParams textParams = new android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT, android.widget.FrameLayout.LayoutParams.MATCH_PARENT);
        trashView.addView(textView, textParams);

        int size = dpToPx(60);
        trashParams = new WindowManager.LayoutParams(
                size, size,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                        : WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE |
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        trashParams.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        trashParams.y = dpToPx(50); 
        trashParams.x = 0; 
        
        if (windowManager != null) {
            windowManager.addView(trashView, trashParams);
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    OverlayConstants.CHANNEL_ID,
                    "Foreground Service Channel",
                    NotificationManager.IMPORTANCE_DEFAULT);
            NotificationManager manager = getSystemService(NotificationManager.class);
            assert manager != null;
            manager.createNotificationChannel(serviceChannel);
        }
    }

    private int getDrawableResourceId(String resType, String name) {
        return getApplicationContext().getResources().getIdentifier(String.format("ic_%s", name), resType,
                getApplicationContext().getPackageName());
    }

    private int dpToPx(int dp) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                Float.parseFloat(dp + ""), mResources.getDisplayMetrics());
    }

    private double pxToDp(int px) {
        return (double) px / mResources.getDisplayMetrics().density;
    }

    private boolean inPortrait() {
        return mResources.getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;
    }

    private boolean canDragThisTouch = false;

    @Override
    public boolean onTouch(View view, MotionEvent event) {
        if (windowManager != null && WindowSetup.enableDrag) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    // If the window is large (expanded mode), only allow dragging from the top 100dp (header)
                    if (params.height > dpToPx(200) && event.getY() > dpToPx(100)) {
                        canDragThisTouch = false;
                        return false;
                    }
                    canDragThisTouch = true;
                    dragging = false;
                    lastX = event.getRawX();
                    lastY = event.getRawY();
                    hasVibratedForTrash = false;

                    if (params.height <= dpToPx(200) && trashView != null) {
                        trashView.setVisibility(View.VISIBLE);
                        trashView.setAlpha(0f);
                        if (windowManager != null) {
                            windowManager.updateViewLayout(trashView, trashParams);
                        }
                        trashView.animate().alpha(1f).setDuration(200).start();
                        isTrashVisible = true;
                    }
                    overTrash = false;
                    break;
                case MotionEvent.ACTION_MOVE:
                    if (!canDragThisTouch) return false;
                    float dx = event.getRawX() - lastX;
                    float dy = event.getRawY() - lastY;
                    if (!dragging && dx * dx + dy * dy < 25) {
                        return false;
                    }
                    lastX = event.getRawX();
                    lastY = event.getRawY();

                    if (!isTrashVisible && params.height <= dpToPx(200) && trashView != null) {
                        trashView.setVisibility(View.VISIBLE);
                        trashView.setAlpha(0f);
                        if (windowManager != null) {
                            windowManager.updateViewLayout(trashView, trashParams);
                        }
                        trashView.animate().alpha(1f).setDuration(200).start();
                        isTrashVisible = true;
                    }

                    // --- Trash proximity detection with magnetic pull ---
                    int trashSnapRadius = dpToPx(70);
                    int trashEscapeRadius = dpToPx(100);

                    // Get the ACTUAL trash center in screen coordinates
                    // (using getLocationOnScreen avoids coordinate system mismatches
                    //  between overlay gravity, trash gravity, and raw touch coords)
                    int trashScreenCenterX = szWindow.x / 2; // fallback
                    int trashScreenCenterY = szWindow.y;      // fallback
                    if (isTrashVisible && trashView != null) {
                        int[] trashLoc = new int[2];
                        trashView.getLocationOnScreen(trashLoc);
                        trashScreenCenterX = trashLoc[0] + trashView.getWidth() / 2;
                        trashScreenCenterY = trashLoc[1] + trashView.getHeight() / 2;
                    }

                    if (isTrashVisible && trashView != null) {
                        float dxT = event.getRawX() - trashScreenCenterX;
                        float dyT = event.getRawY() - trashScreenCenterY;
                        double distToTrash = Math.hypot(dxT, dyT);

                        if (overTrash) {
                            // Already over trash — require larger escape radius to break free
                            if (distToTrash >= trashEscapeRadius) {
                                // Escaped the magnetic pull
                                overTrash = false;
                                hasVibratedForTrash = false;

                                // Reset dx/dy and lastX/lastY to prevent the damping-
                                // corrupted values from flinging the overlay off-screen
                                dx = 0;
                                dy = 0;
                                lastX = event.getRawX();
                                lastY = event.getRawY();

                                // Restore trash circle scale with animation
                                trashView.animate().cancel();
                                trashView.animate()
                                        .scaleX(1.0f).scaleY(1.0f)
                                        .setDuration(150)
                                        .start();
                            }
                        } else {
                            // Not yet over trash — check snap radius
                            if (distToTrash < trashSnapRadius) {
                                overTrash = true;

                                // Haptic vibration on entry
                                if (!hasVibratedForTrash) {
                                    triggerHapticFeedback();
                                    hasVibratedForTrash = true;
                                }

                                // Animate trash circle scale up
                                trashView.animate().cancel();
                                trashView.animate()
                                        .scaleX(TRASH_ACTIVE_SCALE).scaleY(TRASH_ACTIVE_SCALE)
                                        .setDuration(200)
                                        .start();
                            }
                        }
                    }

                    if (overTrash) {
                        // Compute target params.x/y to center the overlay window
                        // on the trash circle. With TOP|LEFT gravity, params.x/y
                        // ARE the screen coordinates of the view's top-left corner.
                        int targetX = trashScreenCenterX - flutterView.getWidth() / 2;
                        int targetY = trashScreenCenterY - flutterView.getHeight() / 2;

                        // Fast lerp with hard-snap: converge 50% per frame,
                        // lock to exact position when within 2px
                        int remainX = targetX - params.x;
                        int remainY = targetY - params.y;
                        params.x += (Math.abs(remainX) < 2) ? remainX : remainX / 2;
                        params.y += (Math.abs(remainY) < 2) ? remainY : remainY / 2;

                        // Apply magnetic damping: resist finger movement away from trash
                        // so the user can't casually drag it out
                        float fingerDxFromTrash = event.getRawX() - trashScreenCenterX;
                        float fingerDyFromTrash = event.getRawY() - trashScreenCenterY;
                        double fingerDist = Math.hypot(fingerDxFromTrash, fingerDyFromTrash);
                        if (fingerDist > 0 && fingerDist < trashEscapeRadius) {
                            float dampingFactor = (float) (TRASH_DAMPING_MIN + (1.0f - TRASH_DAMPING_MIN) * (fingerDist / trashEscapeRadius));
                            lastX = trashScreenCenterX + fingerDxFromTrash * dampingFactor;
                            lastY = trashScreenCenterY + fingerDyFromTrash * dampingFactor;
                        }
                    } else {

                        boolean invertX = WindowSetup.gravity == (Gravity.TOP | Gravity.RIGHT)
                                || WindowSetup.gravity == (Gravity.CENTER | Gravity.RIGHT)
                                || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                        boolean invertY = WindowSetup.gravity == (Gravity.BOTTOM | Gravity.LEFT)
                                || WindowSetup.gravity == Gravity.BOTTOM
                                || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                        int xx = params.x + ((int) dx * (invertX ? -1 : 1));
                        int yy = params.y + ((int) dy * (invertY ? -1 : 1));

                        // Prevent horizontal dragging in expanded mode (height > 200dp)
                        if (params.height > dpToPx(200)) {
                            xx = 0;
                        }

                        params.x = xx;
                        params.y = yy;
                    }

                    if (windowManager != null) {
                        windowManager.updateViewLayout(flutterView, params);
                    }
                    dragging = true;
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    if (!canDragThisTouch) return false;
                    lastYPosition = params.y;

                    if (overTrash) {
                        if (isTrashVisible && trashView != null) {
                            trashView.animate()
                                    .alpha(0f).scaleX(1.0f).scaleY(1.0f)
                                    .setDuration(200)
                                    .withEndAction(() -> {
                                        if (trashView != null) trashView.setVisibility(View.GONE);
                                    }).start();
                            isTrashVisible = false;
                        }
                        overTrash = false;
                        hasVibratedForTrash = false;
                        sendCloseToFlutter();
                        return true;
                    }

                    if (isTrashVisible && trashView != null) {
                        trashView.animate()
                                .alpha(0f).scaleX(1.0f).scaleY(1.0f)
                                .setDuration(200)
                                .withEndAction(() -> {
                                    if (trashView != null) trashView.setVisibility(View.GONE);
                                }).start();
                        isTrashVisible = false;
                    }

                    // Only start snap animation if the user actually dragged.
                    // A simple tap (no drag) must not trigger the animation,
                    // because the Dart-side expand/collapse flow that follows
                    // the tap would race with the timer and corrupt the position.
                    if (dragging && !WindowSetup.positionGravity.equals("none")) {
                        if (windowManager == null)
                            return false;
                        cancelTrayAnimation();
                        windowManager.updateViewLayout(flutterView, params);
                        mTrayTimerTask = new TrayAnimationTimerTask();
                        mTrayAnimationTimer = new Timer();
                        mTrayAnimationTimer.schedule(mTrayTimerTask, 0, 25);
                    }
                    dragging = false;
                    return false;
                default:
                    return false;
            }
            return false;
        }
        return false;
    }

    private void triggerHapticFeedback() {
        if (vibrator == null || !vibrator.hasVibrator()) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(VIBRATION_DURATION_MS, VibrationEffect.DEFAULT_AMPLITUDE));
            } else {
                vibrator.vibrate(VIBRATION_DURATION_MS);
            }
        } catch (Exception e) {
            Log.w("OverlayService", "Vibration failed: " + e.getMessage());
        }
    }

    private class TrayAnimationTimerTask extends TimerTask {
        int mDestX;
        int mDestY;
        WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();

        public TrayAnimationTimerTask() {
            super();
            mDestY = lastYPosition;
            switch (WindowSetup.positionGravity) {
                case "auto":
                    mDestX = (params.x + (flutterView.getWidth() / 2)) <= szWindow.x / 2 ? 0
                            : szWindow.x - flutterView.getWidth();
                    return;
                case "left":
                    mDestX = 0;
                    return;
                case "right":
                    mDestX = szWindow.x - flutterView.getWidth();
                    return;
                default:
                    mDestX = params.x;
                    mDestY = params.y;
                    break;
            }
        }

        @Override
        public void run() {
            mAnimationHandler.post(() -> {
                if (windowManager == null || flutterView == null) {
                    TrayAnimationTimerTask.this.cancel();
                    if (mTrayAnimationTimer != null) mTrayAnimationTimer.cancel();
                    return;
                }
                try {
                    params.x = (2 * (params.x - mDestX)) / 3 + mDestX;
                    params.y = (2 * (params.y - mDestY)) / 3 + mDestY;
                    windowManager.updateViewLayout(flutterView, params);
                } catch (Exception e) {
                    Log.w("OverlayService", "TrayAnimation updateViewLayout failed: " + e.getMessage());
                }
                if (Math.abs(params.x - mDestX) < 2 && Math.abs(params.y - mDestY) < 2) {
                    TrayAnimationTimerTask.this.cancel();
                    if (mTrayAnimationTimer != null) mTrayAnimationTimer.cancel();
                }
            });
        }
    }

}