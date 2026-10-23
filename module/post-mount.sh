#!/system/bin/sh
set -eu
MODDIR=${0%/*}

bind_library() {
    NAME=$1
    SOURCE="$MODDIR/system/odm/lib64/$NAME"
    TARGET="/odm/lib64/$NAME"
    test -f "$SOURCE"
    test -f "$TARGET"
    chown root:root "$SOURCE"
    chmod 0644 "$SOURCE"
    chcon u:object_r:same_process_hal_file:s0 "$SOURCE"
    mount --bind "$SOURCE" "$TARGET"
}

# Hybrid Mount creates the two new backend paths before this phase.
# Replacing a camera HAL library is only safe on the build it was made for: the offsets inside
# libAlgoInterface and the BasicTone classes differ per model. device.json gates the whole group.
DEVICE_JSON=$MODDIR/device.json
flag() {
    [ -f "$DEVICE_JSON" ] && grep -q "\"$1\"[[:space:]]*:[[:space:]]*true" "$DEVICE_JSON"
}

if flag mount_hal_libs; then
    bind_library libBasicTonePhotoX9.so
    bind_library libBasicTonePhotoX10.so
    bind_library libBasicTonePhoto.so
    bind_library libAlgoInterface.so
fi
