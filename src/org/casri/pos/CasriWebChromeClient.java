package org.casri.pos;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.widget.EditText;

/**
 * The piece the shell was missing.
 *
 * An Android WebView with only a WebViewClient silently drops two whole classes
 * of request, because they are delivered to WebChromeClient callbacks that don't
 * exist:
 *
 *   1. Permission requests (camera / microphone) — onPermissionRequest().
 *      Without this, navigator.mediaDevices.getUserMedia() never resolves, so
 *      camera barcode scanning is impossible.
 *
 *   2. JS dialogs — onJsAlert/onJsConfirm/onJsPrompt. Without these,
 *      alert()/confirm()/prompt() return immediately and do nothing, which is
 *      why every confirm-guarded action in the app (logout, delete, add user)
 *      appeared dead until we replaced them with in-page modals.
 *
 * The app no longer depends on native dialogs — it uses its own igConfirm /
 * igPrompt / igAlert modals — but wiring them up here means a stray alert() in
 * future code behaves sanely instead of vanishing.
 *
 * NOTE: granting a PermissionRequest only satisfies the WebView layer. Android
 * still needs the runtime CAMERA permission held by the app itself; that is
 * requested from main.py before the WebView asks.
 */
public class CasriWebChromeClient extends WebChromeClient {

    private final Activity activity;

    public CasriWebChromeClient(Activity activity) {
        this.activity = activity;
    }

    /** Grant camera/mic to our own bundled page. */
    @Override
    public void onPermissionRequest(final PermissionRequest request) {
        if (activity == null) {
            super.onPermissionRequest(request);
            return;
        }
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    // The only page loaded here is our own offline bundle, so it
                    // is safe to grant exactly what it asks for.
                    request.grant(request.getResources());
                } catch (Exception e) {
                    try { request.deny(); } catch (Exception ignored) {}
                }
            }
        });
    }

    @Override
    public boolean onJsAlert(WebView view, String url, String message, final JsResult result) {
        if (activity == null) return super.onJsAlert(view, url, message, result);
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) { result.confirm(); }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    public void onCancel(DialogInterface d) { result.cancel(); }
                })
                .show();
        return true;
    }

    @Override
    public boolean onJsConfirm(WebView view, String url, String message, final JsResult result) {
        if (activity == null) return super.onJsConfirm(view, url, message, result);
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) { result.confirm(); }
                })
                .setNegativeButton(android.R.string.cancel, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) { result.cancel(); }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    public void onCancel(DialogInterface d) { result.cancel(); }
                })
                .show();
        return true;
    }

    @Override
    public boolean onJsPrompt(WebView view, String url, String message,
                              String defaultValue, final JsPromptResult result) {
        if (activity == null) return super.onJsPrompt(view, url, message, defaultValue, result);
        final EditText input = new EditText(activity);
        if (defaultValue != null) input.setText(defaultValue);
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setView(input)
                .setPositiveButton(android.R.string.ok, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        result.confirm(input.getText().toString());
                    }
                })
                .setNegativeButton(android.R.string.cancel, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) { result.cancel(); }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    public void onCancel(DialogInterface d) { result.cancel(); }
                })
                .show();
        return true;
    }
}
