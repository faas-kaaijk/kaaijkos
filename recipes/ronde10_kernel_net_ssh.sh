#!/usr/bin/env bash
set -euo pipefail
export MAKEFLAGS="-j$(nproc)"
mkdir -p /work/stage /work/logs
cd /work/build

for f in cacert.pem curl-8.21.0.tar.xz openssh-10.5p1.tar.gz dosfstools-4.2.tar.gz nano-9.2.tar.xz; do
    [ -s "/work/sources/$f" ] || { echo "FOUT: /work/sources/$f ontbreekt! Draai eerst Stap 1 op de host."; exit 1; }
done
[ -f /work/stage/linux-kaaijkos/boot/vmlinuz-kaaijkos ] || { echo "FOUT: /work/stage/linux-kaaijkos ontbreekt! Draai eerst Stap 1 op de host."; exit 1; }

pkg_done() {
    local NAME="$1" VER="$2" STAGE="/work/stage/$1"
    rm -rf "$STAGE/run" "$STAGE/var/run" "$STAGE/var/lock"
    kpkg pack "$STAGE" "$NAME" "$VER"
    kpkg install "/var/cache/kpkg/${NAME}-${VER}.kpkg.tar.zst"
    ldconfig
    rm -rf "$STAGE"
}

echo "=== [1/6] Linux Kernel 7.3.6-kaaijkos (+ 5.668 gesigneerde modules) ==="
pkg_done linux-kaaijkos 7.3.6
depmod -a 7.3.6-kaaijkos

echo "=== [2/6] Mozilla CA-Certificates (HTTPS root CA's) ==="
S=/work/stage/ca-certificates; rm -rf "$S" && mkdir -p "$S/etc/ssl/certs"
install -v -m644 /work/sources/cacert.pem "$S/etc/ssl/certs/ca-certificates.crt"
ln -sfv certs/ca-certificates.crt "$S/etc/ssl/cert.pem"
ln -sfv ssl/certs/ca-certificates.crt "$S/etc/ca-certificates.crt"
pkg_done ca-certificates 2026

echo "=== [3/6] cURL 8.21.0 (met OpenSSL 4.0.1) ==="
S=/work/stage/curl; rm -rf "$S" curl-8.21.0 && mkdir -p "$S"
tar -xf /work/sources/curl-8.21.0.tar.xz && cd curl-8.21.0
./configure --prefix=/usr \
            --disable-static \
            --with-openssl \
            --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
            --without-libpsl \
            --enable-threaded-resolver
make
make DESTDIR="$S" install
pkg_done curl 8.21.0
cd /work/build && rm -rf curl-8.21.0

echo "=== [4/6] OpenSSH 10.5p1 (incl. sshd.service) ==="
install -v -g sys -m700 -d /var/lib/sshd
getent group sshd >/dev/null || groupadd -g 50 sshd
getent passwd sshd >/dev/null || useradd -c 'sshd PrivSep' -d /var/lib/sshd -g sshd -s /usr/bin/false -u 50 sshd

S=/work/stage/openssh; rm -rf "$S" openssh-10.5p1 && mkdir -p "$S"
tar -xf /work/sources/openssh-10.5p1.tar.gz && cd openssh-10.5p1
./configure --prefix=/usr \
            --sysconfdir=/etc/ssh \
            --with-privsep-path=/var/lib/sshd \
            --with-default-path=/usr/bin \
            --with-superuser-path=/usr/sbin:/usr/bin \
            --with-pid-dir=/run
make
make DESTDIR="$S" install-nokeys
install -v -m755 contrib/ssh-copy-id "$S/usr/bin"
install -v -g sys -m700 -d "$S/var/lib/sshd"

cat >> "$S/etc/ssh/sshd_config" << 'SSH_CFG'

# KaaijkOS 1.0 defaults
PermitRootLogin yes
PasswordAuthentication yes
SSH_CFG

mkdir -p "$S/usr/lib/systemd/system"
cat > "$S/usr/lib/systemd/system/sshd-keygen.service" << 'UNIT_EOF'
[Unit]
Description=Generate OpenSSH Host Keys
Before=sshd.service

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes
UNIT_EOF

cat > "$S/usr/lib/systemd/system/sshd.service" << 'UNIT_EOF'
[Unit]
Description=OpenSSH Daemon (KaaijkOS)
After=network.target sshd-keygen.service
Wants=sshd-keygen.service

[Service]
Type=simple
ExecStart=/usr/sbin/sshd -D
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
UNIT_EOF

pkg_done openssh 10.5p1
systemctl enable sshd.service
cd /work/build && rm -rf openssh-10.5p1

echo "=== [5/6] Dosfstools 4.2 (FAT32 / EFI) ==="
S=/work/stage/dosfstools; rm -rf "$S" dosfstools-4.2 && mkdir -p "$S"
tar -xf /work/sources/dosfstools-4.2.tar.gz && cd dosfstools-4.2
./configure --prefix=/usr \
            --enable-compat-symlinks \
            --mandir=/usr/share/man \
            --docdir=/usr/share/doc/dosfstools-4.2
make
make DESTDIR="$S" install
pkg_done dosfstools 4.2
cd /work/build && rm -rf dosfstools-4.2

echo "=== [6/6] GNU Nano 9.2 ==="
S=/work/stage/nano; rm -rf "$S" nano-9.2 && mkdir -p "$S"
tar -xf /work/sources/nano-9.2.tar.xz && cd nano-9.2
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --enable-utf8 \
            --docdir=/usr/share/doc/nano-9.2
make
make DESTDIR="$S" install
pkg_done nano 9.2
cd /work/build && rm -rf nano-9.2

find /usr/lib /usr/libexec -name '*.la' -delete

echo "=== RONDE 10 KLAAR! ==="
ls -lh /boot/vmlinuz-kaaijkos
curl --version | sed -n '1p'
ssh -V 2>&1
nano --version | sed -n '1p'
echo "--- Totaal: $(kpkg list | wc -l) KaaijkOS pakketten ---"
