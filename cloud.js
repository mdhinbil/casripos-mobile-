// ============================================================
//  Casri POS — cloud sync
// ------------------------------------------------------------
//  The app is bundled offline and runs from a file:// URL inside the APK.
//  The Firebase JS SDK is unreliable from that origin (and would add ~200KB to
//  bundle), so this talks to Firebase over its plain REST APIs with fetch():
//
//    auth  → identitytoolkit.googleapis.com   (email + password)
//    data  → firestore.googleapis.com/v1      (Bearer idToken)
//
//  Model: one Firestore document per storage key, under the signed-in user:
//      casripos/{uid}/keys/{pos_prod | pos_sales | …}
//  Each doc holds the same JSON string the app already keeps in localStorage,
//  plus a millisecond timestamp. Newest timestamp wins — the same last-writer
//  -wins rule Isguul uses, which is safe because one shop edits at a time.
//
//  Per-key documents (rather than one big blob) keep each key under Firestore's
//  1 MB document limit and mean a sales push doesn't rewrite the product list.
// ============================================================

var CLOUD = {
  cfg: null,        // {apiKey, projectId}
  email: "",
  uid: "",
  idToken: "",
  refreshToken: "",
  tokenAt: 0,
  on: false,        // signed in and syncing
  busy: false,
  lastSync: 0,
  lastError: "",
  _timer: null,
  _pending: {}
};

var CLOUD_KEYS = ["pos_biz_list", "pos_current_biz", "pos_prod", "pos_sales",
                  "pos_inv", "pos_acc", "pos_fx"];

// ── config + session persistence ────────────────────────────
function cloudLoad() {
  try {
    var s = JSON.parse(localStorage.getItem("pos_cloud") || "null");
    if (s) {
      CLOUD.cfg = s.cfg || null;
      CLOUD.email = s.email || "";
      CLOUD.uid = s.uid || "";
      CLOUD.refreshToken = s.refreshToken || "";
      CLOUD.lastSync = s.lastSync || 0;
    }
  } catch (e) {}
  if (!CLOUD.cfg && typeof window !== "undefined" && window.BUNDLED_CLOUD_CFG) {
    CLOUD.cfg = window.BUNDLED_CLOUD_CFG;
  }
}
function cloudSave() {
  try {
    localStorage.setItem("pos_cloud", JSON.stringify({
      cfg: CLOUD.cfg, email: CLOUD.email, uid: CLOUD.uid,
      refreshToken: CLOUD.refreshToken, lastSync: CLOUD.lastSync
    }));
  } catch (e) {}
}

function _cloudOnline() {
  return !(typeof navigator !== "undefined" && navigator && navigator.onLine === false);
}

// ── auth ────────────────────────────────────────────────────
function _authURL(method) {
  return "https://identitytoolkit.googleapis.com/v1/accounts:" + method +
         "?key=" + encodeURIComponent(CLOUD.cfg.apiKey);
}
function _cloudAuth(method, email, password) {
  return fetch(_authURL(method), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: email, password: password, returnSecureToken: true })
  }).then(function (r) {
    return r.json().then(function (j) {
      if (!r.ok) {
        var code = (j && j.error && j.error.message) || "AUTH_FAILED";
        throw new Error(code);
      }
      return j;
    });
  });
}
function _applySession(j) {
  CLOUD.idToken = j.idToken;
  CLOUD.refreshToken = j.refreshToken;
  CLOUD.uid = j.localId;
  CLOUD.tokenAt = Date.now();
  CLOUD.on = true;
  cloudSave();
}
// idTokens last an hour; refresh a little early.
function _cloudFreshToken() {
  if (CLOUD.idToken && (Date.now() - CLOUD.tokenAt) < 50 * 60 * 1000) {
    return Promise.resolve(CLOUD.idToken);
  }
  if (!CLOUD.refreshToken) return Promise.reject(new Error("NO_SESSION"));
  return fetch("https://securetoken.googleapis.com/v1/token?key=" + encodeURIComponent(CLOUD.cfg.apiKey), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=refresh_token&refresh_token=" + encodeURIComponent(CLOUD.refreshToken)
  }).then(function (r) { return r.json(); }).then(function (j) {
    if (!j.id_token) throw new Error("REFRESH_FAILED");
    CLOUD.idToken = j.id_token;
    CLOUD.refreshToken = j.refresh_token || CLOUD.refreshToken;
    CLOUD.tokenAt = Date.now();
    cloudSave();
    return CLOUD.idToken;
  });
}

// Friendly text for Firebase's shouty error codes.
function _cloudErrText(code) {
  var m = {
    EMAIL_NOT_FOUND:            T("No account with that email", "Email-kaas akoon ma laha"),
    INVALID_PASSWORD:           T("Wrong password", "Furaha waa khalad"),
    INVALID_LOGIN_CREDENTIALS:  T("Wrong email or password", "Email ama furaha waa khalad"),
    EMAIL_EXISTS:               T("That email already has an account", "Email-kaas akoon ayuu leeyahay"),
    WEAK_PASSWORD:              T("Password must be at least 6 characters", "Furuhu waa inuu ka koobnaadaa 6 xaraf"),
    INVALID_EMAIL:              T("That email address isn't valid", "Email-kaasi sax ma aha"),
    OPERATION_NOT_ALLOWED:      T("Email sign-in is not enabled in Firebase", "Email-ka lagama furin Firebase"),
    NO_SESSION:                 T("Sign in first", "Marka hore gal"),
    TOO_MANY_ATTEMPTS_TRY_LATER: T("Too many attempts — try later", "Isku dayo badan — hadhow isku day")
  };
  if (m[code]) return m[code];
  if (String(code).indexOf("Failed to fetch") >= 0 || String(code).indexOf("NetworkError") >= 0) {
    return T("No internet connection", "Internet ma jiro");
  }
  return String(code || "Error");
}

// ── firestore REST ──────────────────────────────────────────
function _docURL(key) {
  return "https://firestore.googleapis.com/v1/projects/" + CLOUD.cfg.projectId +
         "/databases/(default)/documents/casripos/" + CLOUD.uid + "/keys/" + key;
}
function _putKey(key, token) {
  var raw = localStorage.getItem(key);
  if (raw === null) return Promise.resolve(false);
  var body = { fields: { v: { stringValue: raw }, ts: { integerValue: String(Date.now()) } } };
  return fetch(_docURL(key), {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
    body: JSON.stringify(body)
  }).then(function (r) {
    if (!r.ok) return r.json().then(function (j) {
      throw new Error((j && j.error && j.error.message) || ("HTTP " + r.status));
    });
    return true;
  });
}
function _getKey(key, token) {
  return fetch(_docURL(key), { headers: { Authorization: "Bearer " + token } })
    .then(function (r) {
      if (r.status === 404) return null;          // nothing in the cloud yet
      if (!r.ok) return r.json().then(function (j) {
        throw new Error((j && j.error && j.error.message) || ("HTTP " + r.status));
      });
      return r.json();
    })
    .then(function (doc) {
      if (!doc || !doc.fields || !doc.fields.v) return null;
      return {
        v: doc.fields.v.stringValue,
        ts: parseInt((doc.fields.ts && doc.fields.ts.integerValue) || "0", 10)
      };
    });
}

// ── push / pull ─────────────────────────────────────────────
// Writes are batched: a burst of saves (a sale touches products AND sales)
// becomes one push a moment later instead of several.
function cloudQueue(key) {
  if (!CLOUD.on || CLOUD_KEYS.indexOf(key) < 0) return;
  CLOUD._pending[key] = true;
  if (CLOUD._timer) clearTimeout(CLOUD._timer);
  CLOUD._timer = setTimeout(cloudFlush, 1500);
}
function cloudFlush() {
  if (!CLOUD.on || CLOUD.busy || !_cloudOnline()) return Promise.resolve();
  var keys = Object.keys(CLOUD._pending);
  if (!keys.length) return Promise.resolve();
  CLOUD._pending = {};
  CLOUD.busy = true; _cloudPaint("sync");
  return _cloudFreshToken().then(function (token) {
    return Promise.all(keys.map(function (k) { return _putKey(k, token); }));
  }).then(function () {
    CLOUD.lastSync = Date.now(); CLOUD.lastError = ""; cloudSave();
    CLOUD.busy = false; _cloudPaint("ok");
  }).catch(function (e) {
    // Keep the keys queued so a later flush retries them.
    keys.forEach(function (k) { CLOUD._pending[k] = true; });
    CLOUD.lastError = _cloudErrText(e.message); CLOUD.busy = false; _cloudPaint("err");
  });
}
// Pull every key. Remote wins only when its timestamp is newer than ours.
function cloudPull(force) {
  if (!CLOUD.on || !_cloudOnline()) return Promise.resolve(0);
  CLOUD.busy = true; _cloudPaint("sync");
  var applied = 0;
  return _cloudFreshToken().then(function (token) {
    return Promise.all(CLOUD_KEYS.map(function (k) {
      return _getKey(k, token).then(function (remote) {
        if (!remote) return;
        var localTs = parseInt(localStorage.getItem("pos_ts_" + k) || "0", 10);
        if (!force && remote.ts <= localTs) return;
        if (localStorage.getItem(k) === remote.v) return;
        localStorage.setItem(k, remote.v);
        localStorage.setItem("pos_ts_" + k, String(remote.ts));
        applied++;
      });
    }));
  }).then(function () {
    CLOUD.lastSync = Date.now(); CLOUD.lastError = ""; cloudSave();
    CLOUD.busy = false; _cloudPaint("ok");
    return applied;
  }).catch(function (e) {
    CLOUD.lastError = _cloudErrText(e.message); CLOUD.busy = false; _cloudPaint("err");
    return 0;
  });
}

// What is already in the cloud for this account? Used at sign-in to decide
// direction. NEVER infer this from timestamps: a freshly installed phone has
// NEWER stamps than a PC that uploaded yesterday, so a timestamp-based guess
// would push the empty phone over the real data and destroy it.
function cloudRemoteInfo() {
  return _cloudFreshToken().then(function (token) {
    return Promise.all(CLOUD_KEYS.map(function (k) {
      return _getKey(k, token).then(function (r) { return { k: k, r: r }; });
    }));
  }).then(function (rows) {
    var info = { has: false, businesses: 0, products: 0, sales: 0 };
    rows.forEach(function (row) {
      if (!row.r || !row.r.v) return;
      var n = 0;
      try { var a = JSON.parse(row.r.v); n = Array.isArray(a) ? a.length : 0; } catch (e) {}
      if (row.k === "pos_biz_list") info.businesses = n;
      if (row.k === "pos_prod")     info.products = n;
      if (row.k === "pos_sales")    info.sales = n;
      if (n > 0) info.has = true;
    });
    return info;
  });
}
// Local counts, for the same comparison.
function cloudLocalInfo() {
  function n(k) {
    try { var a = JSON.parse(localStorage.getItem(k) || "[]"); return Array.isArray(a) ? a.length : 0; }
    catch (e) { return 0; }
  }
  return { businesses: n("pos_biz_list"), products: n("pos_prod"), sales: n("pos_sales") };
}

// ── public actions (wired to Settings) ──────────────────────
// Signs in only. The CALLER decides which way data should move, after showing
// the user what is on each side.
function cloudSignIn(email, password, isNew) {
  if (!CLOUD.cfg || !CLOUD.cfg.apiKey) {
    return Promise.reject(new Error(T("Cloud is not configured", "Cloud lama habayn")));
  }
  return _cloudAuth(isNew ? "signUp" : "signInWithPassword", email, password)
    .then(function (j) {
      CLOUD.email = email;
      _applySession(j);
      return cloudRemoteInfo();
    });
}
function cloudSignOut() {
  CLOUD.on = false; CLOUD.idToken = ""; CLOUD.refreshToken = "";
  CLOUD.uid = ""; CLOUD.email = "";
  cloudSave();
  _cloudPaint("off");
}
// Push everything now — used after signing in on a device that already has data.
function cloudPushAll() {
  if (!CLOUD.on) return Promise.resolve();
  CLOUD_KEYS.forEach(function (k) { CLOUD._pending[k] = true; });
  return cloudFlush();
}
// Restore the session on boot, then quietly pull.
function cloudBoot() {
  cloudLoad();
  if (!CLOUD.cfg || !CLOUD.refreshToken) { _cloudPaint("off"); return; }
  CLOUD.on = true;
  _cloudPaint("sync");
  _cloudFreshToken()
    .then(function () { return cloudPull(false); })
    .then(function (n) {
      if (n > 0 && typeof renderPage === "function" && typeof PAGE !== "undefined") {
        location.reload();          // data changed underneath us
      }
    })
    .catch(function (e) {
      CLOUD.lastError = _cloudErrText(e.message);
      _cloudPaint("err");
    });
}
