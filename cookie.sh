#!/data/data/com.termux/files/usr/bin/bash
#
# roblox_cookie_inject.sh
#
# Injects a .ROBLOSECURITY cookie into the Roblox Android app via Frida,
# hooking android.webkit.CookieManager so the value goes in through the
# app's own API (avoids the WebView at-rest encryption problem you'd hit
# with a raw SQLite write into the Cookies DB).
#
# REQUIREMENTS (must already be true before running this):
#   - Device/emulator is rooted, `su` works from Termux
#   - frida-tools installed in Termux:      pip install frida-tools --break-system-packages
#   - frida-server binary for your device's ABI pushed to the device and
#     executable. Get it from: https://github.com/frida/frida/releases
#     Match the version to `frida --version` from frida-tools EXACTLY, and
#     match arch (arm64, x86_64, etc) to your device/emulator.
#
# ── CONFIG ──────────────────────────────────────────────────────────────
ROBLOX_PKG="com.roblox.client"
ROBLOSECURITY_COOKIE="_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|_CAEaAhADIhsKBGR1aWQSEzcwNTE3NzM0OTg5NTUyNDIyMjMoAw.boTqYsDcAQda53j396jMjfiUiE0mp7r-RwKu0mgYOhFDXAiF6OnMHBQdCjHDIieeuyOmri5cB9VGmuB5tvb2didXVonK6F5XHSAqNSW2XUKyqSMmqxjhOhltHn91APu_uDP8Rs5UhtTBDCDUlyU8WU3StKrl65pK8OEq8Y9Nhr1Yi2F0YwmMgk1k_8oxIx18Xs9MM0KyWG4qWY_RkJKPm-Rvbtkg1EnXO01piCGeH3a4xpjSIN162FmlzGcm2wEnxal4bP3wE2ZDsc33zELmMqdNEwjW-FwhFdaJzjJ33OZJtmYYi7LQBXzN_7SpyckRU-rZ55mtaKDkXMt6nQINRxj6sw3Tvmyzp4jXMaiVbQx8ccNuM-3uJvjg4WR7XephsuvwQJGAf9gQzd_EzqKAwTJFSjIWtaEP4n9UkQLCnWGD6mFWV5dqfOACGtLMFxw_lkRZNfPWIaP0S16_UB8YwMJtk6x9OircWo5eugBHVBiI7WI8npVPiFoiTv2CYTLioL317fkFkKdXMLCsl3YkUFVCeOjK1nV14Dvc0Xl2v6foljfgaJfn71Vvn7jKf8VsXp29bCeAk-ikFFFCM_d39N9Hv3CEn2C4azXgYf-ZqxUasAJdctbupNg48Cse-_bLBp6JOyfh3BWBoU-2QjS-hNL4akI6FKKXqdTYSArSRRJy-nP8J3x1fonFgvoTgFTCd4KYG5VUdg9u-kehlbs7dsg6E2Rt38hHgU15DhWaChKBKh5xU8zG1hKcCcffjl2esMSp3205pslrw7j66N6TKDo6Qimp-8xxu1GIo7o3H_idEsAwsBneBmzAKJ_QoC3stym68LXvJdlOuGWnwniFn4Uoad41nXbR_xDuGnumXVFmUfs1SQUPc6Xv_3Osd56FkNtLH8RoiDO-dnK89O10hMpzX27iN_8T-EyCAqqx75j7vNySg2OMkcsNHFk5Kh2LQyEX2Q"
FRIDA_SERVER_DEVICE_PATH="/data/local/tmp/frida-server"
FRIDA_SERVER_LOCAL_PATH="$HOME/frida-server"     # where you pushed/downloaded it
COOKIE_DOMAIN=".roblox.com"
# ────────────────────────────────────────────────────────────────────────

set -e

if [ "$ROBLOSECURITY_COOKIE" = "PASTE_YOUR_.ROBLOSECURITY_VALUE_HERE" ]; then
    echo "[!] Edit ROBLOSECURITY_COOKIE at the top of this script first."
    exit 1
fi

echo "[*] Checking root access..."
su -c "id" >/dev/null 2>&1 || { echo "[!] su failed — device isn't rooted or Termux lacks root."; exit 1; }

echo "[*] Force-stopping $ROBLOX_PKG (clears any stale session state)..."
su -c "am force-stop $ROBLOX_PKG"

echo "[*] Making sure frida-server is on the device and running as root..."
su -c "test -f $FRIDA_SERVER_DEVICE_PATH" || {
    echo "[*] Pushing frida-server to device..."
    su -c "cp $FRIDA_SERVER_LOCAL_PATH $FRIDA_SERVER_DEVICE_PATH"
    su -c "chmod 755 $FRIDA_SERVER_DEVICE_PATH"
}
# Kill any existing instance, then start fresh in the background as root
su -c "pkill -f frida-server" >/dev/null 2>&1 || true
su -c "nohup $FRIDA_SERVER_DEVICE_PATH >/dev/null 2>&1 &"
sleep 2
echo "[*] frida-server running."

# Write the Frida hook script that gets injected into the app process
cat > "$HOME/roblox_hook.js" <<EOF
Java.perform(function () {
    var CookieManager = Java.use("android.webkit.CookieManager");
    var instance = CookieManager.getInstance();

    var cookieString = "ROBLOSECURITY=${ROBLOSECURITY_COOKIE}; Domain=${COOKIE_DOMAIN}; Path=/";

    // Set for both the bare domain and the www subdomain, apps vary in
    // which one they check first.
    instance.setCookie("https://roblox.com", cookieString);
    instance.setCookie("https://www.roblox.com", cookieString);

    var syncMethod = CookieManager.class.getDeclaredMethods();
    for (var i = 0; i < syncMethod.length; i++) {
        if (syncMethod[i].getName() === "flush") {
            instance.flush();
            break;
        }
    }

    console.log("[hook] ROBLOSECURITY cookie injected via CookieManager.");

    // Also hook setCookie so you can see in the console whenever the app
    // itself sets/reads cookies, useful for confirming your value stuck
    // and for finding the exact domain string the app expects.
    CookieManager.setCookie.overload("java.lang.String", "java.lang.String").implementation = function (url, value) {
        console.log("[app set cookie] url=" + url + " value=" + value);
        return this.setCookie(url, value);
    };
});
EOF

echo "[*] Spawning $ROBLOX_PKG under Frida and injecting cookie hook..."
echo "[*] (Ctrl+C to detach once you see the app open and logged in.)"
frida -U -f "$ROBLOX_PKG" -l "$HOME/roblox_hook.js" --no-pause
