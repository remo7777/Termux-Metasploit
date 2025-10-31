#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export CC=clang
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$PREFIX/include -I$PREFIX/include/libxml2"
export CFLAGS="$CPPFLAGS -Wno-implicit-function-declaration -Wno-deprecated-declarations -Wno-incompatible-function-pointer-types"
export LDFLAGS="-L$PREFIX/lib"
export NOKOGIRI_USE_SYSTEM_LIBRARIES=1
export C_INCLUDE_PATH="/data/data/com.termux/files/usr/lib/ruby/gems/3.4.0/gems/nokogiri-1.18.9/ext/nokogiri/ports/aarch64-linux-android/libgumbo/1.0.0-nokogiri/include"

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
  (pkg update -y && pkg upgrade -y -o Dpkg::Options::="--force-confnew") &>/dev/null &
  spin22 "Packages" " \bDone " "Update & Upgrade"
}

install_deps() {
  (pkg install -y python ruby git curl wget make clang autoconf bison \
    coreutils ncurses ncurses-utils termux-tools binutils \
    libffi libgmp libpcap libsqlite gumbo-parser gumbo-parser-static libgrpc libtool libxml2 libxslt \
    openssl readline apr apr-util postgresql unzip zip tar \
    termux-elf-cleaner pkg-config) &>/dev/null &
  spin22 "Packages" " \bDone " "Installing"
  pip install --no-cache-dir requests &>/dev/null || true
}

fetch_msf() {
  msg "Cloning Metasploit"
  rm -rf "$MSF_DIR"
  (curl --fail --retry 3 --location --output "$TMPDIR/metasploit-${MSF_VERSION}.tar.gz" \
    "https://github.com/rapid7/metasploit-framework/archive/${MSF_VERSION}.tar.gz" --silent) &>/dev/null &
  progress "metasploit-$MSF_VERSION"
  echo -e "\e[32m[*] Extracting new version of Metasploit Framework...\e[0m"
  mkdir -p "$MSF_DIR"
  tar zxf "$TMPDIR/metasploit-$MSF_VERSION.tar.gz" --strip-components=1 -C "$MSF_DIR"
  rm -f "$TMPDIR/metasploit-$MSF_VERSION.tar.gz"
}

setup_ruby() {
  msg "Installing Ruby gems"
  gem update --system --quiet
  if ! gem list bundler -i >/dev/null 2>&1; then
    msg "Installing bundler..."
    gem install bundler --no-document
  else
    msg "Bundler already installed: $(bundle -v)"
  fi

  cd "$MSF_DIR" || { msg "❌ Could not enter $MSF_DIR"; return 1; }

  local NOKOGIRI_VERSION
  NOKOGIRI_VERSION=$(grep -E "nokogiri \([0-9]" Gemfile.lock | head -n1 | sed -E "s/.*\(([0-9.]+)\).*/\1/")

  if [ -n "$NOKOGIRI_VERSION" ]; then
    msg "Installing nokogiri v$NOKOGIRI_VERSION with include path fix..."
    gumbo_inc=$(find "$PREFIX/lib/ruby/gems" -type f -name nokogiri_gumbo.h 2>/dev/null | head -n1)
    if [ -n "$gumbo_inc" ]; then
      gumbo_dir=$(dirname "$gumbo_inc")
      extra_flag="-I$gumbo_dir"
      msg "Found nokogiri_gumbo.h → $gumbo_dir"
    else
      extra_flag=""
      msg "nokogiri_gumbo.h not found; using default include"
    fi

    gem install nokogiri -v "$NOKOGIRI_VERSION" -- \
      --use-system-libraries \
      --with-xml2-include="$PREFIX/include/libxml2" \
      --with-xml2-lib="$PREFIX/lib" \
      --with-xslt-include="$PREFIX/include" \
      --with-xslt-lib="$PREFIX/lib" \
      --with-cflags="$CFLAGS $extra_flag"
  else
    msg "⚠️ Nokogiri version not found in Gemfile.lock, skipping direct install"
  fi

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

postgres_db() {
  LOGFILE="$HOME/.pg_msf.log"
  echo -e "\e[32m[*] Running fixes...\e[0m"
  sed -i "s@/etc/resolv.conf@$PREFIX/etc/resolv.conf@g" "$PREFIX"/opt/metasploit-framework/lib/net/dns/resolver.rb

  echo -e "\e[32m[*] Cleaning old PostgreSQL cluster...\e[0m"
  pg_ctl -D "$PREFIX"/var/lib/postgresql stop >/dev/null 2>&1 || true
  rm -rf "$PREFIX"/var/lib/postgresql/*
  mkdir -p "$PREFIX"/var/lib/postgresql

  echo -e "\e[32m[*] Initializing new PostgreSQL cluster...\e[0m"
  initdb "$PREFIX"/var/lib/postgresql \
    --username=msf_user \
    --pwfile=<(echo 123456) \
    --auth=trust

  echo -e "\e[32m[*] Starting PostgreSQL...\e[0m"
  pg_ctl -D "$PREFIX"/var/lib/postgresql start -l "$LOGFILE" -o "-c logging_collector=off"

  echo -e "\e[32m[*] Creating Metasploit database.yml...\e[0m"
  mkdir -p "$MSF_DIR"/config
  cat <<- EOF > "$MSF_DIR"/config/database.yml
  development:
    adapter: "postgresql"
    database: "msf_database"
    username: "msf_user"
    password: "123456"
    port: 5432
    host: "localhost"
    pool: 256
    timeout: 5

  production:
    adapter: "postgresql"
    database: "msf_database"
    username: "msf_user"
    password: "123456"
    port: 5432
    host: "localhost"
    pool: 256
    timeout: 5
EOF

  echo -e "\e[32m[*] Creating msf_database...\e[0m"
  createdb -O msf_user msf_database -U msf_user

  echo -e "\e[32m[*] PostgreSQL setup complete. Logs: $LOGFILE\e[0m"
  echo -e "\e[32m[*] Run 'msfconsole' and use 'db_status' to verify.\e[0m"
}

# ---------- Main ----------
trap "NORM; exit" 2
banner "${figftemp}" "${logotemp}" >>${user}
cat "${user}"
echo ""
update_system
install_deps
fetch_msf
setup_ruby
symlinks
postgres_db
echo ""
msg "Done! Run: msfconsole"
