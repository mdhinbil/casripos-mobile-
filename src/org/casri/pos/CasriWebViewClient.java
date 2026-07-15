package org.casri.pos;

import android.content.Intent;
import android.net.Uri;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;

/**
 * WebView client for the bundled (offline) Casri POS app.
 *
 * The app itself is loaded from file:// inside the APK, so those navigations
 * MUST stay in the WebView. Anything the WebView can't render itself — tel:,
 * mailto:, sms:, whatsapp:/wa.me (receipt sharing), geo:/maps, intent:, and
 * external http(s) — is handed to the phone's apps (dialer, WhatsApp, browser).
 *
 * Without this, those links show net::ERR_UNKNOWN_URL_SCHEME.
 */
public class CasriWebViewClient extends WebViewClient {

    private boolean handle(WebView view, String url) {
        if (url == null) return false;
        String u = url.toLowerCase();

        // Our own bundled app + inline schemes → keep inside the WebView.
        if (u.startsWith("file:")   || u.startsWith("data:")  ||
            u.startsWith("blob:")   || u.startsWith("about:")  ||
            u.startsWith("javascript:")) {
            return false;
        }

        boolean external =
            u.startsWith("tel:")      || u.startsWith("mailto:") ||
            u.startsWith("sms:")      || u.startsWith("mms:")    ||
            u.startsWith("geo:")      || u.startsWith("whatsapp:") ||
            u.startsWith("intent:")   ||
            u.startsWith("http://")   || u.startsWith("https://");

        if (!external) return false;

        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            view.getContext().startActivity(i);
        } catch (Exception e) {
            // No app installed to handle it — swallow so the WebView doesn't
            // show an ugly ERR_UNKNOWN_URL_SCHEME page.
        }
        return true;
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        return handle(view, request.getUrl().toString());
    }

    @Override
    @SuppressWarnings("deprecation")
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return handle(view, url);
    }
}
