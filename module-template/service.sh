#!/system/bin/sh
MODDIR=${0%/*}
RVPATH=/data/adb/Morphe/${MODDIR##*/}.apk
. "$MODDIR/config"

# Detect root solution
detect_root_solution() {
	if [ -f /data/adb/ksu/bin/ksud ]; then
		echo "kernelsu"
	elif [ -f /data/adb/ap/bin/apd ]; then
		echo "apatch"
	elif [ -f /data/adb/magisk/magisk ]; then
		echo "magisk"
	else
		echo "unknown"
	fi
}

ROOT_SOL=$(detect_root_solution)

err() {
	[ ! -f "$MODDIR/err" ] && cp "$MODDIR/module.prop" "$MODDIR/err"
	sed -i "s/^des.*/description=⚠️ Needs reflash: '${1}'/g" "$MODDIR/module.prop"
}

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 1; done
until [ -d "/sdcard/Android" ]; do sleep 1; done
while
	BASEPATH=$(pm path "$PKG_NAME" 2>&1 </dev/null)
	SVCL=$?
	[ $SVCL = 20 ]
do sleep 2; done

run() {
	if [ $SVCL != 0 ]; then
		err "app not installed"
		return
	fi
	sleep 4

	BASEPATH=${BASEPATH##*:} BASEPATH=${BASEPATH%/*}
	if [ ! -d "$BASEPATH/lib" ]; then
		err "mount failed (ROM issue)"
		return
	fi
	VERSION=$(dumpsys package "$PKG_NAME" 2>&1 | grep -m1 versionName) VERSION="${VERSION#*=}"
	if [ "$VERSION" != "$PKG_VER" ] && [ "$VERSION" ]; then
		err "version mismatch (installed:${VERSION}, module:$PKG_VER)"
		return
	fi
	
	# Unmount existing mounts
	grep "$PKG_NAME" /proc/mounts | while read -r line; do
		mp=${line#* } mp=${mp%% *}
		umount -l "${mp%%\\*}"
	done
	
	# Set SELinux context
	if ! chcon u:object_r:apk_data_file:s0 "$RVPATH"; then
		err "apk not found"
		return
	fi
	
	# Mount based on root solution
	if [ "$ROOT_SOL" = "kernelsu" ] || [ "$ROOT_SOL" = "apatch" ]; then
		nsenter -t1 -m mount -o bind "$RVPATH" "$BASEPATH/base.apk"
	else
		mount -o bind "$RVPATH" "$BASEPATH/base.apk"
	fi
	
	am force-stop "$PKG_NAME"
	[ -f "$MODDIR/err" ] && mv -f "$MODDIR/err" "$MODDIR/module.prop"
}

run