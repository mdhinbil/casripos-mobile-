"""
Casri POS — native Android shell that runs the BUNDLED web app offline.

Unlike the Isguul shell (which loads a hosted URL), this packs index.html /
app.js / styles.css inside the APK and loads them from the phone's local
storage via a file:// URL. The till therefore works with ZERO internet — the
right behaviour for a shop counter. To ship an update you rebuild + reinstall.

Run locally:  python main.py       (desktop fallback — real WebView is Android)
Build APK:    buildozer android debug   (or the GitHub Actions workflow)
"""

import os

# Kivy config must come before any other kivy import
from kivy.config import Config
Config.set('graphics', 'width',  '390')
Config.set('graphics', 'height', '844')
Config.set('graphics', 'resizable', True)

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.clock import Clock
from kivy.utils import platform
from kivy.core.window import Window
from kivy.metrics import dp


def _app_dir():
    """Absolute path to the folder holding the bundled web files.

    python-for-android unpacks the packaged source into the app's private
    directory and points ANDROID_ARGUMENT at it. We prefer that; on desktop
    (and as a fallback) we use this file's own directory.
    """
    cand = []
    env = os.environ.get('ANDROID_ARGUMENT')
    if env:
        cand.append(env)
    try:
        cand.append(os.path.dirname(os.path.abspath(__file__)))
    except Exception:
        pass
    cand.append(os.getcwd())
    for d in cand:
        try:
            if d and os.path.exists(os.path.join(d, 'index.html')):
                return d
        except Exception:
            pass
    return cand[-1] if cand else '.'


def _index_url():
    """file:// URL to the bundled index.html (forward slashes — Android is Linux)."""
    path = os.path.join(_app_dir(), 'index.html').replace('\\', '/')
    if not path.startswith('/'):
        path = '/' + path
    return 'file://' + path


APP_URL = _index_url()


# Detect Android WebView availability
WEBVIEW_AVAILABLE = False
try:
    if platform == 'android':
        from jnius import autoclass, PythonJavaClass, java_method
        PythonActivity = autoclass('org.kivy.android.PythonActivity')
        WebView = autoclass('android.webkit.WebView')
        WebViewClient = autoclass('android.webkit.WebViewClient')
        # Custom client (Java in src/) that routes tel:/mailto:/wa.me/maps links
        # out to the phone's apps. Falls back to the stock client if missing.
        try:
            CasriWebViewClient = autoclass('org.casri.pos.CasriWebViewClient')
        except Exception:
            CasriWebViewClient = WebViewClient
        WebSettings = autoclass('android.webkit.WebSettings')
        ViewGroupLayoutParams = autoclass('android.view.ViewGroup$LayoutParams')
        WEBVIEW_AVAILABLE = True
except Exception:
    pass


def _mount_webview():
    """Create and attach the native Android WebView pointing at the bundled app.

    Runs on Android's UI thread via a Runnable. We use addContentView (NOT
    setContentView) so Kivy's SDL render surface stays intact — replacing it
    crashes SDL's HWUI render thread with SIGABRT.
    """
    activity = PythonActivity.mActivity

    class _MountTask(PythonJavaClass):
        __javainterfaces__ = ['java/lang/Runnable']
        __javacontext__ = 'app'

        @java_method('()V')
        def run(self):
            try:
                webview = WebView(activity)
                s = webview.getSettings()
                s.setJavaScriptEnabled(True)
                s.setDomStorageEnabled(True)      # localStorage — where Casri POS keeps its data
                s.setDatabaseEnabled(True)
                s.setLoadWithOverviewMode(True)
                s.setUseWideViewPort(True)
                s.setSupportZoom(False)
                # Bundled offline app → the WebView MUST be allowed to read the
                # local files. (The hosted Isguul shell keeps this false.)
                s.setAllowFileAccess(True)
                s.setAllowContentAccess(True)
                try:
                    # Let the file:// page load its sibling file:// assets
                    # (app.js, styles.css). Deprecated but still honoured.
                    s.setAllowFileAccessFromFileURLs(True)
                    s.setAllowUniversalAccessFromFileURLs(True)
                except Exception:
                    pass
                s.setMediaPlaybackRequiresUserGesture(False)
                s.setCacheMode(WebSettings.LOAD_DEFAULT)
                webview.setWebViewClient(CasriWebViewClient())

                # Enable Chrome DevTools remote inspection — connect Chrome on
                # PC to chrome://inspect to debug the WebView.
                WebView.setWebContentsDebuggingEnabled(True)

                params = ViewGroupLayoutParams(
                    ViewGroupLayoutParams.MATCH_PARENT,
                    ViewGroupLayoutParams.MATCH_PARENT,
                )
                activity.addContentView(webview, params)
                webview.loadUrl(APP_URL)
                App.get_running_app()._webview = webview
                print('[Casri] WebView mounted, loading', APP_URL)
            except Exception as exc:
                import traceback
                print('[Casri] WebView mount FAILED:', exc)
                traceback.print_exc()

    activity.runOnUiThread(_MountTask())


class SplashScreen(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(orientation='vertical',
                         padding=dp(40), spacing=dp(20), **kwargs)
        self.add_widget(Label(
            text='[b]Casri[color=00b8d9] POS[/color][/b]',
            markup=True, font_size=dp(38),
            color=(1, 1, 1, 1), size_hint_y=0.6,
        ))
        self.add_widget(Label(
            text='Loading...',
            font_size=dp(14), color=(0.8, 0.8, 0.9, 1),
        ))


class DesktopFallback(BoxLayout):
    """Shown when running on desktop (no native WebView). Dev preview only."""
    def __init__(self, **kwargs):
        super().__init__(orientation='vertical', padding=dp(24),
                         spacing=dp(16), **kwargs)
        self.add_widget(Label(
            text='[b]Casri[color=00b8d9] POS[/color][/b]',
            markup=True, font_size=dp(32),
            size_hint_y=None, height=dp(60),
            color=(0.04, 0.09, 0.16, 1),
        ))
        self.add_widget(Label(
            text=(
                'Run this on Android to see the WebView.\n\n'
                'Bundled app entry:\n[color=1a6ef5]' + APP_URL + '[/color]'
            ),
            markup=True, font_size=dp(13), halign='center',
            color=(0.1, 0.1, 0.14, 1),
        ))


class CasriApp(App):
    title = 'Casri POS'
    icon = 'assets/icon.png'
    _webview = None

    def build(self):
        Window.clearcolor = (0.04, 0.09, 0.16, 1)   # navy #0a1628
        self.splash = SplashScreen()
        if WEBVIEW_AVAILABLE:
            # Slight delay so the Kivy window settles before we add the WebView
            Clock.schedule_once(lambda *_: _mount_webview(), 0.3)
        else:
            Clock.schedule_once(lambda *_: self._show_desktop_fallback(), 0.3)
        return self.splash

    def _show_desktop_fallback(self):
        self.root_window.remove_widget(self.splash)
        self.root_window.add_widget(DesktopFallback())

    def on_pause(self):
        return True   # keep alive when minimised

    def on_resume(self):
        pass

    def on_start(self):
        # Wire Android hardware back button to WebView history
        if platform == 'android':
            Window.bind(on_keyboard=self._on_key)

    def _on_key(self, window, key, scancode, codepoint, modifier):
        # 27 = ESC (Android maps the hardware back button to ESC)
        if key == 27 and self._webview is not None:
            try:
                if self._webview.canGoBack():
                    self._webview.goBack()
                    return True
            except Exception:
                pass
        return False


if __name__ == '__main__':
    CasriApp().run()
