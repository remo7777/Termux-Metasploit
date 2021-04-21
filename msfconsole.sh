#!/data/data/com.termux/files/usr/bin/sh
SCRIPT_NAME=$(basename "$0")
METASPLOIT_PATH="${HOME}/metasploit-framework"

# set ruby version
android=$(getprop ro.build.version.release)
if [ ${android%%.*} -ge 7 ]; then
    RUBYVER=3.0.0
else
    RUBYVER=2.6.0
fi
# Fix ruby bigdecimal extensions linking error.
case "$(uname -m)" in
	aarch64)
		export LD_PRELOAD="${PREFIX}/lib/ruby/$RUBYVER/aarch64-linux-android/bigdecimal.so:$LD_PRELOAD"
		;;
	arm*)
		export LD_PRELOAD="${PREFIX}/lib/ruby/$RUBYVER/arm-linux-androideabi/bigdecimal.so:$LD_PRELOAD"
		;;
	i686)
		export LD_PRELOAD="${PREFIX}/lib/ruby/$RUBYVER/i686-linux-android/bigdecimal.so:$LD_PRELOAD"
		;;
	x86_64)
		export LD_PRELOAD="${PREFIX}/lib/ruby/$RUBYVER/x86_64-linux-android/bigdecimal.so:$LD_PRELOAD"
		;;
	*)
		;;
esac
case "$SCRIPT_NAME" in
	msfconsole|msfvenom)
		exec ruby "$METASPLOIT_PATH/$SCRIPT_NAME" "$@"
		;;
	*)
		echo "[!] Unknown Metasploit command '$SCRIPT_NAME'."
		exit 1
		;;
esac
