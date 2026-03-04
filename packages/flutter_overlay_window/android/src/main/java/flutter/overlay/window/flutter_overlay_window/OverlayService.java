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

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

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

    // --- Native audio recording (AudioRecord-based, runs inside the foreground service) ---
    private android.media.AudioRecord audioRecord;
    private Thread recordingThread;
    private volatile boolean nativeRecording = false;
    private String nativeRecordingPath;
    private static final int NATIVE_SAMPLE_RATE = 16000;
    private static final int NATIVE_CHANNEL_CONFIG = android.media.AudioFormat.CHANNEL_IN_MONO;
    private static final int NATIVE_AUDIO_FORMAT = android.media.AudioFormat.ENCODING_PCM_16BIT;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ---- Native recording from foreground service context ----

    public static String startNativeRecordingStatic(String path) {
        if (instance == null) {
            Log.e("OverlayRecording", "startNativeRecordingStatic: instance is NULL");
            return null;
        }
        return instance.startNativeRecording(path);
    }

    public static String stopNativeRecordingStatic() {
        if (instance == null) return null;
        return instance.stopNativeRecording();
    }

    public static void cancelNativeRecordingStatic() {
        if (instance != null) instance.cancelNativeRecording();
    }

    @android.annotation.SuppressLint("MissingPermission")
    private String startNativeRecording(String path) {
        if (nativeRecording) {
            stopNativeRecording();
        }

        nativeRecordingPath = path;

        try {
            File parentDir = new File(path).getParentFile();
            if (parentDir != null) parentDir.mkdirs();

            Log.d("OverlayRecording", "Starting AudioRecord. pid=" + android.os.Process.myPid()
                    + " uid=" + android.os.Process.myUid());

            int bufferSize = android.media.AudioRecord.getMinBufferSize(
                    NATIVE_SAMPLE_RATE, NATIVE_CHANNEL_CONFIG, NATIVE_AUDIO_FORMAT);
            if (bufferSize <= 0) bufferSize = NATIVE_SAMPLE_RATE * 2; // 1 second fallback

            // Use AudioRecord.Builder with setContext() to set the correct PID
            // in the attribution source. The legacy constructor always sets pid=-1,
            // causing AudioFlinger to mute the stream for background apps.
            final long token = android.os.Binder.clearCallingIdentity();
            try {
                android.media.AudioFormat audioFormat = new android.media.AudioFormat.Builder()
                        .setSampleRate(NATIVE_SAMPLE_RATE)
                        .setChannelMask(NATIVE_CHANNEL_CONFIG)
                        .setEncoding(NATIVE_AUDIO_FORMAT)
                        .build();

                audioRecord = new android.media.AudioRecord.Builder()
                        .setAudioSource(android.media.MediaRecorder.AudioSource.VOICE_RECOGNITION)
                        .setAudioFormat(audioFormat)
                        .setBufferSizeInBytes(bufferSize)
                        .setContext(OverlayService.this)
                        .build();
            } finally {
                android.os.Binder.restoreCallingIdentity(token);
            }

            if (audioRecord.getState() != android.media.AudioRecord.STATE_INITIALIZED) {
                Log.e("OverlayRecording", "AudioRecord init failed, state=" + audioRecord.getState());
                audioRecord.release();
                audioRecord = null;
                return null;
            }

            audioRecord.startRecording();
            nativeRecording = true;

            // Write PCM data on a background thread
            final int readBufSize = bufferSize;
            recordingThread = new Thread(() -> {
                java.io.RandomAccessFile raf = null;
                try {
                    raf = new java.io.RandomAccessFile(path, "rw");
                    // Write placeholder WAV header (44 bytes), will update later
                    raf.write(new byte[44]);

                    byte[] buffer = new byte[readBufSize];
                    long totalBytes = 0;
                    while (nativeRecording) {
                        int read = audioRecord.read(buffer, 0, buffer.length);
                        if (read > 0) {
                            raf.write(buffer, 0, read);
                            totalBytes += read;
                        }
                    }

                    // Go back and write the correct WAV header
                    raf.seek(0);
                    writeWavHeader(raf, totalBytes, NATIVE_SAMPLE_RATE, 1);
                    Log.d("OverlayRecording", "WAV written: " + path
                            + " (" + (totalBytes + 44) + " bytes, "
                            + String.format("%.1f", totalBytes / (double)(NATIVE_SAMPLE_RATE * 2)) + "s)");
                } catch (Exception e) {
                    Log.e("OverlayRecording", "Recording thread error: " + e.getMessage(), e);
                } finally {
                    if (raf != null) {
                        try { raf.close(); } catch (Exception ignored) {}
                    }
                }
            }, "OverlayAudioRecorder");
            recordingThread.start();

            Log.d("OverlayRecording", "AudioRecord started: " + path);
            return path;
        } catch (Exception e) {
            Log.e("OverlayRecording", "AudioRecord start failed: " + e.getMessage(), e);
            if (audioRecord != null) {
                try { audioRecord.release(); } catch (Exception ignored) {}
                audioRecord = null;
            }
            return null;
        }
    }

    private void writeWavHeader(java.io.RandomAccessFile raf, long totalAudioLen,
                                int sampleRate, int channels) throws java.io.IOException {
        long totalDataLen = totalAudioLen + 36;
        long byteRate = (long) sampleRate * channels * 2;

        byte[] header = new byte[44];
        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        header[4] = (byte)(totalDataLen & 0xff);
        header[5] = (byte)((totalDataLen >> 8) & 0xff);
        header[6] = (byte)((totalDataLen >> 16) & 0xff);
        header[7] = (byte)((totalDataLen >> 24) & 0xff);
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0; // chunk size
        header[20] = 1; header[21] = 0; // PCM format
        header[22] = (byte) channels; header[23] = 0;
        header[24] = (byte)(sampleRate & 0xff);
        header[25] = (byte)((sampleRate >> 8) & 0xff);
        header[26] = (byte)((sampleRate >> 16) & 0xff);
        header[27] = (byte)((sampleRate >> 24) & 0xff);
        header[28] = (byte)(byteRate & 0xff);
        header[29] = (byte)((byteRate >> 8) & 0xff);
        header[30] = (byte)((byteRate >> 16) & 0xff);
        header[31] = (byte)((byteRate >> 24) & 0xff);
        header[32] = (byte)(channels * 2); header[33] = 0; // block align
        header[34] = 16; header[35] = 0; // bits per sample
        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        header[40] = (byte)(totalAudioLen & 0xff);
        header[41] = (byte)((totalAudioLen >> 8) & 0xff);
        header[42] = (byte)((totalAudioLen >> 16) & 0xff);
        header[43] = (byte)((totalAudioLen >> 24) & 0xff);
        raf.write(header);
    }

    private String stopNativeRecording() {
        if (!nativeRecording || audioRecord == null) {
            return nativeRecordingPath;
        }

        nativeRecording = false;

        // Wait for recording thread to finish writing
        if (recordingThread != null) {
            try { recordingThread.join(3000); } catch (InterruptedException ignored) {}
            recordingThread = null;
        }

        try {
            audioRecord.stop();
        } catch (Exception e) {
            Log.e("OverlayRecording", "AudioRecord stop failed: " + e.getMessage());
        }
        audioRecord.release();
        audioRecord = null;

        Log.d("OverlayRecording", "AudioRecord stopped: " + nativeRecordingPath
                + " (" + new File(nativeRecordingPath).length() + " bytes)");
        return nativeRecordingPath;
    }

    private void cancelNativeRecording() {
        String path = stopNativeRecording();
        if (path != null) {
            new File(path).delete();
        }
        nativeRecordingPath = null;
    }

    /**
     * Convert AAC/M4A file to 16kHz mono 16-bit PCM WAV using MediaExtractor + MediaCodec.
     */
    private void convertM4aToWav(String inputPath, String outputPath) throws IOException {
        android.media.MediaExtractor extractor = new android.media.MediaExtractor();
        extractor.setDataSource(inputPath);

        // Find audio track
        int audioTrackIndex = -1;
        android.media.MediaFormat inputFormat = null;
        for (int i = 0; i < extractor.getTrackCount(); i++) {
            android.media.MediaFormat fmt = extractor.getTrackFormat(i);
            String mime = fmt.getString(android.media.MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("audio/")) {
                audioTrackIndex = i;
                inputFormat = fmt;
                break;
            }
        }
        if (audioTrackIndex < 0 || inputFormat == null) {
            extractor.release();
            throw new IOException("No audio track found in " + inputPath);
        }

        extractor.selectTrack(audioTrackIndex);
        String mime = inputFormat.getString(android.media.MediaFormat.KEY_MIME);

        // Configure decoder
        android.media.MediaCodec decoder = android.media.MediaCodec.createDecoderByType(mime);
        decoder.configure(inputFormat, null, null, 0);
        decoder.start();

        // Collect all decoded PCM
        java.io.ByteArrayOutputStream pcmStream = new java.io.ByteArrayOutputStream();
        android.media.MediaCodec.BufferInfo info = new android.media.MediaCodec.BufferInfo();
        boolean inputDone = false;
        boolean outputDone = false;
        long timeoutUs = 10000;

        while (!outputDone) {
            // Feed input
            if (!inputDone) {
                int inIdx = decoder.dequeueInputBuffer(timeoutUs);
                if (inIdx >= 0) {
                    java.nio.ByteBuffer inBuf = decoder.getInputBuffer(inIdx);
                    int sampleSize = extractor.readSampleData(inBuf, 0);
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inIdx, 0, 0, 0,
                                android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                        inputDone = true;
                    } else {
                        decoder.queueInputBuffer(inIdx, 0, sampleSize,
                                extractor.getSampleTime(), 0);
                        extractor.advance();
                    }
                }
            }

            // Drain output
            int outIdx = decoder.dequeueOutputBuffer(info, timeoutUs);
            if (outIdx >= 0) {
                if (info.size > 0) {
                    java.nio.ByteBuffer outBuf = decoder.getOutputBuffer(outIdx);
                    outBuf.position(info.offset);
                    outBuf.limit(info.offset + info.size);
                    byte[] chunk = new byte[info.size];
                    outBuf.get(chunk);
                    pcmStream.write(chunk);
                }
                decoder.releaseOutputBuffer(outIdx, false);
                if ((info.flags & android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true;
                }
            }
        }
        // Get the actual output sample rate from the decoder (before stopping!)
        android.media.MediaFormat outputFormat = decoder.getOutputFormat();
        int actualSampleRate = outputFormat.containsKey(android.media.MediaFormat.KEY_SAMPLE_RATE)
                ? outputFormat.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
                : NATIVE_SAMPLE_RATE;
        int actualChannels = outputFormat.containsKey(android.media.MediaFormat.KEY_CHANNEL_COUNT)
                ? outputFormat.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)
                : 1;

        decoder.stop();
        decoder.release();
        extractor.release();

        byte[] pcmData = pcmStream.toByteArray();
        pcmStream.close();

        Log.d("OverlayRecording", "Decoder output: sampleRate=" + actualSampleRate
                + " channels=" + actualChannels + " pcmBytes=" + pcmData.length);

        // Write WAV file with the actual decoder output format
        writeWavFile(outputPath, pcmData, actualSampleRate, actualChannels);
    }

    private void writeWavFile(String filePath, byte[] pcmData, int sampleRate, int channels) throws IOException {
        long totalAudioLen = pcmData.length;
        long totalDataLen = totalAudioLen + 36;
        long byteRate = (long) sampleRate * channels * 2;

        byte[] header = new byte[44];
        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        header[4] = (byte)(totalDataLen & 0xff);
        header[5] = (byte)((totalDataLen >> 8) & 0xff);
        header[6] = (byte)((totalDataLen >> 16) & 0xff);
        header[7] = (byte)((totalDataLen >> 24) & 0xff);
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        header[16] = 16; // PCM chunk size
        header[20] = 1;  // PCM format
        header[22] = (byte) channels;
        header[24] = (byte)(sampleRate & 0xff);
        header[25] = (byte)((sampleRate >> 8) & 0xff);
        header[26] = (byte)((sampleRate >> 16) & 0xff);
        header[27] = (byte)((sampleRate >> 24) & 0xff);
        header[28] = (byte)(byteRate & 0xff);
        header[29] = (byte)((byteRate >> 8) & 0xff);
        header[30] = (byte)((byteRate >> 16) & 0xff);
        header[31] = (byte)((byteRate >> 24) & 0xff);
        header[32] = (byte)(channels * 2); // block align
        header[34] = 16; // bits per sample
        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        header[40] = (byte)(totalAudioLen & 0xff);
        header[41] = (byte)((totalAudioLen >> 8) & 0xff);
        header[42] = (byte)((totalAudioLen >> 16) & 0xff);
        header[43] = (byte)((totalAudioLen >> 24) & 0xff);

        FileOutputStream fos = new FileOutputStream(filePath);
        fos.write(header);
        fos.write(pcmData);
        fos.flush();
        fos.close();
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverLay", "Destroying the overlay window service");
        cancelNativeRecording();
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
        instance = this;
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
            } else if (call.method.equals("startRecording")) {
                String path = call.argument("path");
                try {
                    String resultPath = startNativeRecording(path);
                    if (resultPath != null) {
                        result.success(resultPath);
                    } else {
                        result.error("RECORDING_ERROR", "AudioRecord init failed (service=" + this + ")", null);
                    }
                } catch (Exception e) {
                    Log.e("OverlayRecording", "startRecording handler error: " + e.getMessage(), e);
                    result.error("RECORDING_ERROR", e.getMessage(), null);
                }
            } else if (call.method.equals("stopRecording")) {
                try {
                    String resultPath = stopNativeRecording();
                    result.success(resultPath);
                } catch (Exception e) {
                    Log.e("OverlayRecording", "stopRecording handler error: " + e.getMessage(), e);
                    result.error("RECORDING_ERROR", e.getMessage(), null);
                }
            } else if (call.method.equals("cancelRecording")) {
                cancelNativeRecording();
                result.success(null);
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        } else {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        }
        Log.d("OverlayRecording", "startForeground called with MICROPHONE type, pid=" + android.os.Process.myPid());
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