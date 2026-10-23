#!/system/bin/sh
# Collect everything needed to port OmniCam Muse to this phone.
#
# Run on the device with root (KernelSU / Magisk):
#   adb push tools/port/dump_device.sh /data/local/tmp/
#   adb shell su -c "sh /data/local/tmp/dump_device.sh"
#   adb pull /sdcard/omnicam-dump-<model>-<date>.tar.gz
#
# Options:
#   --apk        also copy the camera and gallery APKs (needed to re-fingerprint symbols.json;
#                adds a few hundred MB)
#   --out DIR    write the tarball to DIR instead of /sdcard
#
# Nothing here modifies the system: every step reads or copies.

set -u

INCLUDE_APK=0
OUT_DIR=/sdcard
while [ $# -gt 0 ]; do
    case "$1" in
        --apk) INCLUDE_APK=1 ;;
        --out) shift; OUT_DIR=${1:-/sdcard} ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

ID=$(id -u)
if [ "$ID" != "0" ]; then
    echo "run as root: adb shell su -c 'sh $0'" >&2
    exit 1
fi

MODEL=$(getprop ro.product.model 2>/dev/null | tr -d ' \r\n')
DEVICE=$(getprop ro.product.device 2>/dev/null | tr -d ' \r\n')
[ -n "$MODEL" ] || MODEL=unknown
[ -n "$DEVICE" ] || DEVICE=unknown
STAMP=$(date +%Y%m%d-%H%M%S)
NAME="omnicam-dump-${MODEL}-${STAMP}"
WORK=/data/local/tmp/$NAME
rm -rf "$WORK"
mkdir -p "$WORK/configs" "$WORK/prefs" "$WORK/db" "$WORK/apk"

say() { echo "[dump] $*"; }

say "model=$MODEL device=$DEVICE"

# --- build and product properties -------------------------------------------------------------
{
    getprop | sed -n 's/^\[\(.*\)\]: \[\(.*\)\]$/\1=\2/p' | \
        grep -E '^(ro\.(product|build|system\.build|vendor\.build|boot|oplus|realme|coloros|oppo)|persist\.(sys\.|vendor\.camera)|dalvik\.vm\.version)' 
} > "$WORK/props.txt" 2>/dev/null

{
    echo "# packages"
    echo "build: $(getprop ro.build.display.id) / Android $(getprop ro.build.version.release) / sdk $(getprop ro.build.version.sdk)"
    echo "coloros: $(getprop ro.build.version.oplusrom) $(getprop ro.build.version.oplusrom.display)"
    echo "realmeui: $(getprop ro.build.version.realmeui)"
    echo "first_api_level: $(getprop ro.product.first_api_level)"
    echo
    for pkg in com.oplus.camera com.coloros.gallery3d com.oplus.camera.unit.sdk; do
        echo "== $pkg"
        dumpsys package "$pkg" 2>/dev/null | grep -E 'versionName|versionCode|codePath|firstInstallTime' | head -6
    done
    echo
    echo "# camera app paths"
    pm path com.oplus.camera 2>/dev/null
    pm path com.coloros.gallery3d 2>/dev/null
    echo
    echo "# Hal / camera libs"
    ls -l /odm/lib64/ 2>/dev/null | grep -Ei 'algo|camera|basictone|combinelut|msnative|hal\.' 
} > "$WORK/packages.txt" 2>/dev/null

# --- /odm camera configuration ----------------------------------------------------------------
{
    echo "# /odm/etc/camera (depth 3)"
    find /odm/etc/camera -maxdepth 3 2>/dev/null | sort
    echo
    echo "# sizes of the files the module binds"
    for f in \
        /odm/etc/camera/config/camera_unit_config \
        /odm/etc/camera/config/camera_unit_feature_config.protobuf \
        /odm/etc/camera/config/oplus_camera_config \
        /odm/etc/camera/config/oplus_camera_algo_switch_config \
        /odm/etc/camera/config/oplus_camera_aps_config \
        /odm/etc/camera/config/oplus_camera_preview_decision_config.json \
        /odm/etc/camera/CameraHWConfiguration.config \
        /odm/etc/camera/conf_tuning_params.json \
        /odm/etc/audio/audio_policy_volumes.xml
    do
        if [ -f "$f" ]; then echo "present $(stat -c '%s %a %U:%G' "$f" 2>/dev/null) $f"
        else echo "missing $f"; fi
    done
} > "$WORK/odm_camera_tree.txt" 2>/dev/null

for f in camera_unit_config camera_unit_feature_config.protobuf oplus_camera_config \
         oplus_camera_algo_switch_config oplus_camera_aps_config \
         oplus_camera_preview_decision_config.json; do
    [ -f "/odm/etc/camera/config/$f" ] && cp -f "/odm/etc/camera/config/$f" "$WORK/configs/$f"
done
for f in CameraHWConfiguration.config conf_tuning_params.json gamma_preview_sdr_conf.json \
         gamma_quick_sdr_conf.json gamma_preview_hdr_conf.json; do
    [ -f "/odm/etc/camera/$f" ] && cp -f "/odm/etc/camera/$f" "$WORK/configs/$f"
done

# Lists, not contents: these trees are hundreds of MB.
{
    echo "# meishe_lut"
    ls -l /odm/etc/camera/meishe_lut 2>/dev/null
    echo
    echo "# filters_lut"
    ls -l /odm/etc/camera/filters_lut 2>/dev/null
    echo
    echo "# basictone"
    find /odm/etc/camera/basictone -maxdepth 2 2>/dev/null | sort | head -400
} > "$WORK/lut_and_basictone.txt" 2>/dev/null

# --- library fingerprints ---------------------------------------------------------------------
{
    for lib in libAlgoInterface.so libBasicTonePhoto.so libBasicTonePhotoX9.so \
               libBasicTonePhotoX10.so libCombineLut.so libCombineLutJni.so libmsnativefilter.so; do
        for dir in /odm/lib64 /odm/lib64/camera /product/lib64 /system/lib64 /vendor/lib64; do
            if [ -f "$dir/$lib" ]; then
                echo "$(sha256sum "$dir/$lib" 2>/dev/null) $dir/$lib"
                echo "    size=$(stat -c %s "$dir/$lib") mtime=$(stat -c %y "$dir/$lib")"
            fi
        done
    done
} > "$WORK/lib_sha256.txt" 2>/dev/null

# --- camera state -----------------------------------------------------------------------------
{
    echo "# sensors"
    dumpsys media.camera 2>/dev/null | grep -E '^\s*(Camera [0-9]+|Device [0-9]+|Camera ID|Facing|Sensor)' | head -80
} > "$WORK/camera_state.txt" 2>/dev/null

CAM=/data/user/0/com.oplus.camera
GAL=/data/user/0/com.coloros.gallery3d
[ -f "$CAM/shared_prefs/override_config_data.xml" ] && cp -f "$CAM/shared_prefs/override_config_data.xml" "$WORK/prefs/"
[ -f "$GAL/shared_prefs/business_featureSwitch_config.xml" ] && cp -f "$GAL/shared_prefs/business_featureSwitch_config.xml" "$WORK/prefs/"
for f in "$CAM"/databases/mode_data.db "$CAM"/databases/*.db; do
    [ -f "$f" ] && cp -f "$f" "$WORK/db/$(basename "$f")"
done
{
    echo "# camera private files"
    ls -l "$CAM/files" 2>/dev/null | head -60
    echo "# camera feature flags (sqlite dumps if sqlite3 exists)"
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$CAM/databases/mode_data.db" ]; then
        sqlite3 "$CAM/databases/mode_data.db" '.tables' 2>/dev/null
        sqlite3 "$CAM/databases/mode_data.db" 'select * from mode_data;' 2>/dev/null | head -200
    fi
} > "$WORK/camera_files.txt" 2>/dev/null

# --- APKs (optional) --------------------------------------------------------------------------
if [ "$INCLUDE_APK" = "1" ]; then
    for pkg in com.oplus.camera com.coloros.gallery3d; do
        path=$(pm path "$pkg" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
        if [ -n "$path" ]; then
            say "copying $pkg from $path"
            cp -f "$path" "$WORK/apk/$(basename "$path")"
        fi
    done
fi

say "packing"
TAR="$OUT_DIR/$NAME.tar.gz"
tar czf "$TAR" -C /data/local/tmp "$NAME" 2>/dev/null || {
    echo "packaging failed; the directory is still at $WORK" >&2
    exit 1
}
rm -rf "$WORK"
say "done: $TAR ($(stat -c %s "$TAR" 2>/dev/null) bytes)"
echo
echo "Pull it to the PC with:  adb pull $TAR"
echo "Then upload the tarball in the chat."
