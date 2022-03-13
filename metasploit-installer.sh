#!/data/data/com.termux/files/usr/bin/bash

PREFIX=/data/data/com.termux/files/usr
TMPDIR=/data/data/com.termux/files/usr/tmp
MSF_VERSION=6.0.24
progress() {

local pid=$!
local delay=0.25
while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do

        for i in "$(if test -e $TMPDIR/*.gz; then cd $TMPDIR/;du -h *.gz | awk '{print $1}';fi)"
do
        tput civis
        echo -ne "\033[34m\r[*] Downloading...\e[33m[\033[36mMetasploit-${MSF_VERSION} \033[32m$i\033[33m]\033[0m   ";
        sleep $delay
        printf "\b\b\b\b\b\b\b\b";
done
done
printf "   \b\b\b\b\b"
tput cnorm
printf "\e[1;33m [Done]\e[0m";
echo "";

}
spin () {

local pid=$!
local delay=0.05
local spinstr='|/-\'
while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
	tput civis
        printf "\e[1;34m\r[*] \e[1;32mDependency packages install  [\e[1;33m%c\e[1;32m]\e[0m  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "   \b\b\b"
    tput cnorm
    printf "\e[1;33m[Done]\e[0m"
    echo ""
}


#(curl --fail --retry 3 --location --output "$TMPDIR/metasploit-${MSF_VERSION}.tar.gz" \
        #"https://github.com/rapid7/metasploit-framework/archive/${MSF_VERSION}.tar.gz" --silent) &> /dev/null & progress

# Lock terminal to prevent sending text input and special key
# combinations that may break installation process.
#stty -echo -icanon time 0 min 0 intr undef quit undef susp undef

# Use trap to unlock terminal at exit.
trap "tput reset; tput cnorm; exit" 2

if [ "$(id -u)" = "0" ]; then
	echo "[!] Do not install Termux packages as root :)"
	exit 1
fi
clear
echo;
#(apt update;apt install wget busybox -y;wget -O $TMPDIR/metasploit.txt https://raw.githubusercontent.com/remo7777/Termux-Metasploit/master/logo.txt) &> /dev/null
#cat $TMPDIR/metasploit.txt;
echo;
echo -e "\e[32mDependency packages install...\e[0m"
sleep 5;
(apt upgrade -y;apt install apr apr-util autoconf bison clang coreutils curl findutils git libffi libgmp libiconv libpcap libsqlite libtool libxml2 libxslt make ncurses ncurses ncurses-utils openssl pkg-config postgresql readline resolv-conf tar termux-elf-cleaner ruby2 termux-tools unzip wget zip zlib openssl-1.1 -y;ln -sf $PREFIX/lib/openssl-1.1/*.so.1.1 $PREFIX/lib/;) &> /dev/null & spin
#cp .msfconsole $TMPDIR/msfconsole -u;
echo -e "\e[32m[*] Downloading Metasploit Framework...\e[0m"
(mkdir -p "$TMPDIR";
rm -f "$TMPDIR/metasploit-$MSF_VERSION.tar.gz";) &> /dev/null

#curl --fail --retry 3 --location --output "$TMPDIR/metasploit-$MSF_VERSION.tar.gz" \
	#"https://github.com/rapid7/metasploit-framework/archive/$MSF_VERSION.tar.gz"
(curl --fail --retry 3 --location --output "$TMPDIR/metasploit-${MSF_VERSION}.tar.gz" \
        "https://github.com/rapid7/metasploit-framework/archive/${MSF_VERSION}.tar.gz" --silent) &> /dev/null & progress

echo -e "\e[32m[*] Removing previous version Metasploit Framework...\e[0m"
rm -rf "$PREFIX"/opt/metasploit-framework

echo -e "\e[32m[*] Extracting new version of Metasploit Framework...\e[0m"
mkdir -p "$PREFIX"/opt/metasploit-framework
tar zxf "$TMPDIR/metasploit-$MSF_VERSION.tar.gz" --strip-components=1 \
	-C "$PREFIX"/opt/metasploit-framework
sleep 2
rm -rf $TMPDIR/metasploit-$MSF_VERSION.tar.gz

echo -e "\e[32m[*] Installing 'rubygems-update' if necessary..."
if [ "$(gem list -i rubygems-update 2>/dev/null)" = "false" ]; then
	gem install --no-document --verbose rubygems-update
fi

echo -e "\e[32m[*] Updating Ruby gems...\e[0m"
update_rubygems

echo -e "\e[32m[*] Installing 'bundler:2.2.11'...\e[0m"
gem install --no-document --verbose bundler:2.2.11

echo -e "\e32m[*] Installing Metasploit dependencies (may take long time)...\e[0m"
cd "$PREFIX"/opt/metasploit-framework
bundle config build.nokogiri --use-system-libraries
bundle install --jobs=2 --verbose

echo -e "\e[32m[*] Running fixes...\e[0m"
sed -i "s@/etc/resolv.conf@$PREFIX/etc/resolv.conf@g" "$PREFIX"/opt/metasploit-framework/lib/net/dns/resolver.rb
find "$PREFIX"/opt/metasploit-framework -type f -executable -print0 | xargs -0 -r termux-fix-shebang
find "$PREFIX"/lib/ruby/gems -type f -iname \*.so -print0 | xargs -0 -r termux-elf-cleaner

echo -e "\e[32m[*] Setting up PostgreSQL database...\e[0m"
mkdir -p "$PREFIX"/opt/metasploit-framework/config
cat <<- EOF > "$PREFIX"/opt/metasploit-framework/config/database.yml
production:
  adapter: postgresql
  database: msf_database
  username: msf
  password:
  host: 127.0.0.1
  port: 5432
  pool: 75
  timeout: 5
EOF
mkdir -p "$PREFIX"/var/lib/postgresql
pg_ctl -D "$PREFIX"/var/lib/postgresql stop > /dev/null 2>&1 || true
if ! pg_ctl -D "$PREFIX"/var/lib/postgresql start --silent; then
    initdb "$PREFIX"/var/lib/postgresql
    pg_ctl -D "$PREFIX"/var/lib/postgresql start --silent
fi
if [ -z "$(psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='msf'")" ]; then
    createuser msf
fi
if [ -z "$(psql -l | grep msf_database)" ]; then
    createdb msf_database
fi
rm -rf $PREFIX/bin/{msfconsole,msfd,msfrpc,msfrpcd,msfvenom} > /dev/null 2>&1 || true
# download file from git msfconsole.sh
#wget -O "$TMPDIR"/msfconsole.sh https://raw.githubusercontent.com/remo7777/Termux-Metasploit/master/msfconsole.sh
# patch
# Wrapper.
install -Dm700 $TMPDIR/msfconsole \
	"$PREFIX"/bin/msfconsole
#chmod 700 $PREFIX"/bin/msfconsole;
for i in msfd msfrpc msfrpcd msfvenom; do
	ln -sfr "$PREFIX"/bin/msfconsole "$PREFIX"/bin/$i
done
rm -rf $TMPDIR/msfconsole
killall postgres &> /dev/null
#printf("\n");
echo -e "\e[32m[*] Metasploit Framework installation finished.\e[0m"
#stty echo
cd
exit 0
