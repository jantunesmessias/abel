package io.github.jantunesmessias.flutter_app_adapter;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

public final class AppAdapterPlugin implements
        FlutterPlugin,
        ActivityAware,
        MethodChannel.MethodCallHandler,
        PluginRegistry.NewIntentListener {
    private static final String CHANNEL = "app_adapter/runtime_configuration";
    private static final Pattern KEY = Pattern.compile("^[A-Z][A-Z0-9_]{0,63}$");
    private static final Pattern SECRET = Pattern.compile(
            "(SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_?KEY)",
            Pattern.CASE_INSENSITIVE
    );

    private MethodChannel channel;
    private ActivityPluginBinding activityBinding;
    private Intent latestIntent;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        latestIntent = binding.getActivity().getIntent();
        binding.addOnNewIntentListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(
            ActivityPluginBinding binding
    ) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    @Override
    public boolean onNewIntent(Intent intent) {
        latestIntent = intent;
        final ActivityPluginBinding binding = activityBinding;
        if (binding != null) {
            binding.getActivity().setIntent(intent);
        }
        return false;
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!"readLaunchOverlay".equals(call.method)) {
            result.notImplemented();
            return;
        }
        result.success(readOverlay());
    }

    private Map<String, String> readOverlay() {
        final Map<String, String> output = new HashMap<>();
        final Intent intent = latestIntent;
        final Bundle extras = intent == null ? null : intent.getExtras();
        if (extras == null) {
            return output;
        }
        for (String key : extras.keySet()) {
            final String value = extras.getString(key);
            if (KEY.matcher(key).matches()
                    && !SECRET.matcher(key).find()
                    && value != null
                    && value.length() <= 4096
                    && output.size() < 64) {
                output.put(key, value);
            }
        }
        return output;
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeOnNewIntentListener(this);
        }
        activityBinding = null;
        latestIntent = null;
    }
}
