#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
MSF_DIR="$PREFIX/opt/metasploit-framework"
TMPDIR="$PREFIX/tmp/"
MSF_VERSION=6.4.85
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

FILES=(pbanner progress)

for f in "${FILES[@]}"; do
  if [[ -f "$LIB_DIR/$f" ]]; then
    . "$LIB_DIR/$f"
  else
    echo "Warning: $LIB_DIR/$f not found"
  fi
done

# ---------- Helpers ----------
msg() { echo -e "\n[\e[32m✔\e[0m] $1"; }

# ---------- Steps ----------
update_system() {
  # msg "Updating packages"
  (pkg update -y && pkg upgrade -y -o Dpkg::Options::="--force-confnew") &>/dev/null &
  spin22 "Packages" " \bDone " "Update & Upgrade"
}

install_deps() {
  # msg "Installing dependencies"
  (pkg install -y python ruby git curl wget make clang autoconf bison \
    coreutils ncurses ncurses-utils termux-tools binutils \
    libffi libgmp libpcap libsqlite libgrpc libtool libxml2 libxslt \
    openssl readline apr apr-util postgresql unzip zip tar \
    termux-elf-cleaner pkg-config) &>/dev/null &
  spin22 "Packages" " \bDone " "Installing"
  pip install --no-cache-dir requests &>/dev/null
}

fetch_msf() {
  msg "Cloning Metasploit"
  rm -rf "$MSF_DIR"
  # git clone --depth=1 https://github.com/rapid7/metasploit-framework "$MSF_DIR"
  (curl --fail --retry 3 --location --output "$TMPDIR/metasploit-${MSF_VERSION}.tar.gz" \
    "https://github.com/rapid7/metasploit-framework/archive/${MSF_VERSION}.tar.gz" --silent) &>/dev/null &
  progress "metasploit-$MSF_VERSION"
  echo -e "\e[32m[*] Extracting new version of Metasploit Framework...\e[0m"
  mkdir -p "$MSF_DIR"
  tar zxf "$TMPDIR/metasploit-$MSF_VERSION.tar.gz" --strip-components=1 \
    -C "$MSF_DIR"
  sleep 2
  rm -rf $TMPDIR/metasploit-$MSF_VERSION.tar.gz
}

setup_ruby() {
  msg "Installing Ruby gems"
  # Update RubyGems
  gem update --system --quiet
  # Ensure bundler is installed
  if ! gem list bundler -i >/dev/null 2>&1; then
    msg "Installing bundler..."
    gem install bundler --no-document
  else
    msg "Bundler already installed: $(bundle -v)"
  fi
  # Enter project directory
  cd "$MSF_DIR" || { msg "❌ Could not enter $MSF_DIR"; return 1; }
  # Extract nokogiri version from Gemfile.lock
  local NOKOGIRI_VERSION
  NOKOGIRI_VERSION=$(grep -E "nokogiri \([0-9]" Gemfile.lock \
    | head -n1 \
    | sed -E "s/.*\(([0-9.]+)\).*/\1/")
  if [ -n "$NOKOGIRI_VERSION" ]; then
    msg "Installing nokogiri v$NOKOGIRI_VERSION with CFLAGS workaround..."
    gem install nokogiri -v "$NOKOGIRI_VERSION" -- \
      --with-cflags="-Wno-implicit-function-declaration -Wno-deprecated-declarations -Wno-incompatible-function-pointer-types" \
      --use-system-libraries
  else
    msg "⚠️ Nokogiri version not found in Gemfile.lock, skipping direct install"
  fi
  # Install and update dependencies inside MSF directory
  bundle install -j"$(nproc --all)" --quiet
  gem install actionpack --no-document
  bundle update activesupport
  bundle update --bundler
  bundle install -j"$(nproc --all)" --quiet
  msg "✔ Ruby gems installed successfully"
}

symlinks() {
  msg "Linking executables"
  for f in msfconsole msfvenom msfrpcd; do ln -sf "$MSF_DIR/$f" "$PREFIX/bin/$f"; done
  termux-elf-cleaner "$PREFIX"/lib/ruby/gems/*/gems/pg-*/lib/pg_ext.so || true
}

# ---------- Main ----------
# Use trap to unlock terminal at exit.
trap "NORM; exit" 2
banner "${figftemp}" "${logotemp}" >>${user}
cat "${user}"
echo ""
# check_internet
update_system
install_deps
fetch_msf
setup_ruby
symlinks
echo ""
msg "Done! Run: msfconsole"
