#!/data/data/com.termux/files/usr/bin/bash
#
# roblox_cookie_sqlite_inject.sh
#
# Directly edits the Roblox Android app's WebView Cookies SQLite DB to
# insert a .ROBLOSECURITY cookie, using root via Termux (`su`) — no
# Frida, no adb, no PC required.
#
# CAVEAT: some Android WebView versions store cookie values encrypted
# at rest (encrypted_value column, tied to the app's own Keystore key).
# If that's the case here, this script will still run and "succeed" but
# Roblox may still show logged-out, because it can't decrypt a value it
# never encrypted itself. There's no way to know in advance without
# testing on your specific device/app version.
#
# REQUIREMENTS:
#   - Rooted device/emulator, `su` works from Termux
#   - sqlite3 installed:  pkg install sqlite -y
#
# ── CONFIG ──────────────────────────────────────────────────────────────
ROBLOX_PKG="com.roblox.client"
ROBLOSECURITY_COOKIE="_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|_CAEaAhADIhsKBGR1aWQSEzcwNTE3NzM0OTg5NTUyNDIyMjMoAw.boTqYsDcAQda53j396jMjfiUiE0mp7r-RwKu0mgYOhFDXAiF6OnMHBQdCjHDIieeuyOmri5cB9VGmuB5tvb2didXVonK6F5XHSAqNSW2XUKyqSMmqxjhOhltHn91APu_uDP8Rs5UhtTBDCDUlyU8WU3StKrl65pK8OEq8Y9Nhr1Yi2F0YwmMgk1k_8oxIx18Xs9MM0KyWG4qWY_RkJKPm-Rvbtkg1EnXO01piCGeH3a4xpjSIN162FmlzGcm2wEnxal4bP3wE2ZDsc33zELmMqdNEwjW-FwhFdaJzjJ33OZJtmYYi7LQBXzN_7SpyckRU-rZ55mtaKDkXMt6nQINRxj6sw3Tvmyzp4jXMaiVbQx8ccNuM-3uJvjg4WR7XephsuvwQJGAf9gQzd_EzqKAwTJFSjIWtaEP4n9UkQLCnWGD6mFWV5dqfOACGtLMFxw_lkRZNfPWIaP0S16_UB8YwMJtk6x9OircWo5eugBHVBiI7WI8npVPiFoiTv2CYTLioL317fkFkKdXMLCsl3YkUFVCeOjK1nV14Dvc0Xl2v6foljfgaJfn71Vvn7jKf8VsXp29bCeAk-ikFFFCM_d39N9Hv3CEn2C4azXgYf-ZqxUasAJdctbupNg48Cse-_bLBp6JOyfh3BWBoU-2QjS-hNL4akI6FKKXqdTYSArSRRJy-nP8J3x1fonFgvoTgFTCd4KYG5VUdg9u-kehlbs7dsg6E2Rt38hHgU15DhWaChKBKh5xU8zG1hKcCcffjl2esMSp3205pslrw7j66N6TKDo6Qimp-8xxu1GIo7o3H_idEsAwsBneBmzAKJ_QoC3stym68LXvJdlOuGWnwniFn4Uoad41nXbR_xDuGnumXVFmUfs1SQUPc6Xv_3Osd56FkNtLH8RoiDO-dnK89O10hMpzX27iN_8T-EyCAqqx75j7vNySg2OMkcsNHFk5Kh2LQyEX2Q"
COOKIE_DB_PATH="/data/data/${ROBLOX_PKG}/app_webview/Default/Cookies"
COOKIE_HOST=".roblox.com"
WORKDIR="$HOME/roblox_cookie_work"
# ────────────────────────────────────────────────────────────────────────

set -e

if [ "$ROBLOSECURITY_COOKIE" = "PASTE_YOUR_.ROBLOSECURITY_VALUE_HERE" ]; then
    echo "[!] Edit ROBLOSECURITY_COOKIE at the top of this script first."
    exit 1
fi

command -v sqlite3 >/dev/null 2>&1 || { echo "[!] sqlite3 not found — run: pkg install sqlite -y"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 not found — run: pkg install python -y"; exit 1; }

echo "[*] Checking root access..."
su -c "id" >/dev/null 2>&1 || { echo "[!] su failed — device isn't rooted or Termux lacks root."; exit 1; }

mkdir -p "$WORKDIR"
LOCAL_DB="$WORKDIR/Cookies"

echo "[*] Force-stopping $ROBLOX_PKG so the DB isn't locked/in use..."
su -c "am force-stop $ROBLOX_PKG"

echo "[*] Checking cookie DB exists at $COOKIE_DB_PATH ..."
su -c "test -f $COOKIE_DB_PATH" || {
    echo "[!] Cookie DB not found at that path. It may not exist until the app"
    echo "    has opened a WebView once (e.g. shown a login screen at least once)."
    echo "    Open the app, get to the login screen, force-close it, then rerun this."
    exit 1
}

echo "[*] Grabbing the app's UID/GID so we can restore ownership after editing..."
APP_UID_GID=$(su -c "stat -c '%u:%g' $COOKIE_DB_PATH")
echo "    -> $APP_UID_GID"

echo "[*] Copying DB out to $LOCAL_DB for editing..."
su -c "cp $COOKIE_DB_PATH $LOCAL_DB"
su -c "chmod 666 $LOCAL_DB"

echo "[*] Inspecting cookies table schema..."
sqlite3 "$LOCAL_DB" "PRAGMA table_info(cookies);" | cut -d'|' -f2

echo "[*] Removing any existing ROBLOSECURITY row for this host..."
sqlite3 "$LOCAL_DB" "DELETE FROM cookies WHERE name = 'ROBLOSECURITY' AND host_key LIKE '%roblox.com%';"

NOW_UTC=$(( $(date +%s) * 1000000 + 11644473600000000 ))   # chromium epoch (microseconds since 1601)
EXPIRES_UTC=$(( NOW_UTC + (60*60*24*365*1000000) ))        # ~1 year out

echo "[*] Inserting new ROBLOSECURITY cookie row..."
python3 - "$LOCAL_DB" "$COOKIE_HOST" "$ROBLOSECURITY_COOKIE" "$NOW_UTC" "$EXPIRES_UTC" <<'PYEOF'
import sqlite3, sys
db, host, value, now_utc, expires_utc = sys.argv[1:6]
con = sqlite3.connect(db)
cur = con.cursor()
cols = [r[1] for r in cur.execute("PRAGMA table_info(cookies)").fetchall()]

row = {
    "creation_utc": int(now_utc),
    "host_key": host,
    "top_frame_site_key": "",
    "name": "ROBLOSECURITY",
    "value": value,
    "encrypted_value": b"",
    "path": "/",
    "expires_utc": int(expires_utc),
    "is_secure": 1,
    "is_httponly": 1,
    "last_access_utc": int(now_utc),
    "last_update_utc": int(now_utc),
    "has_expires": 1,
    "is_persistent": 1,
    "priority": 1,
    "samesite": 0,
    "source_scheme": 2,
    "source_port": 443,
    "is_same_party": 0,
}
use_cols = [c for c in row if c in cols]
placeholders = ",".join("?" for _ in use_cols)
sql = f"INSERT INTO cookies ({','.join(use_cols)}) VALUES ({placeholders})"
cur.execute(sql, [row[c] for c in use_cols])
con.commit()
con.close()
print(f"[*] Inserted using columns: {use_cols}")
PYEOF

echo "[*] Copying edited DB back over the original..."
su -c "cp $LOCAL_DB $COOKIE_DB_PATH"

echo "[*] Restoring original ownership ($APP_UID_GID) so the app can read it..."
su -c "chown $APP_UID_GID $COOKIE_DB_PATH"
su -c "chmod 600 $COOKIE_DB_PATH"

echo "[*] Clearing -wal/-shm sidecar files so Roblox doesn't load a stale cached copy..."
su -c "rm -f ${COOKIE_DB_PATH}-wal ${COOKIE_DB_PATH}-shm" || true

echo "[*] Done. Launching $ROBLOX_PKG..."
su -c "monkey -p $ROBLOX_PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1

echo "[*] Check the app. If still logged out, this DB likely uses encrypted_value"
echo "    rather than plaintext, which a raw SQL write can't satisfy."
