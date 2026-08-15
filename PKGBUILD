# Maintainer: hugobugomugo <hugo@hugobugomugo.de>
pkgname=modlinq-git
pkgver=r6.967f969
pkgrel=1
pkgdesc="Mod manager for Zenless Zone Zero, Wuthering Waves and Neverness to Everness"
arch=('x86_64')
url="https://github.com/hugobugomugo/Modlinq"
license=('MIT')
depends=(
    'gtk3'
    'glib2'
    'libx11'
)
makedepends=(
    'git'
    'flutter'
    'clang'
    'cmake'
    'ninja'
    'pkgconf'
)
provides=('modlinq')
conflicts=('modlinq')
source=("git+https://github.com/hugobugomugo/Modlinq.git")
sha256sums=('SKIP')

pkgver() {
    cd "$srcdir/Modlinq"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

prepare() {
    cd "$srcdir/Modlinq/mod_manager_flutter"
    export PUB_CACHE="$srcdir/pub_cache"
    flutter pub get
}

build() {
    cd "$srcdir/Modlinq/mod_manager_flutter"
    export PUB_CACHE="$srcdir/pub_cache"
    flutter build linux --release
}

package() {
    cd "$srcdir/Modlinq"

    install -dm755 "$pkgdir/opt/modlinq"
    install -dm755 "$pkgdir/usr/bin"
    install -dm755 "$pkgdir/usr/share/applications"
    install -dm755 "$pkgdir/usr/share/pixmaps"
    install -dm755 "$pkgdir/usr/share/icons/hicolor/256x256/apps"

    cp -r mod_manager_flutter/build/linux/x64/release/bundle/* "$pkgdir/opt/modlinq/"

    if [ -f "assets/icon.png" ]; then
        install -Dm644 assets/icon.png "$pkgdir/opt/modlinq/data/flutter_assets/assets/icon.png"
        install -Dm644 assets/icon.png "$pkgdir/usr/share/pixmaps/modlinq.png"
        install -Dm644 assets/icon.png "$pkgdir/usr/share/icons/hicolor/256x256/apps/modlinq.png"
    fi

    cat > "$pkgdir/usr/share/applications/modlinq.desktop" << 'EOF'
[Desktop Entry]
Name=Modlinq
Comment=Mod manager for Zenless Zone Zero, Wuthering Waves and Neverness to Everness
Exec=/opt/modlinq/modlinq
Icon=/opt/modlinq/data/flutter_assets/assets/icon.png
Terminal=false
Type=Application
Categories=Utility;Game;
StartupNotify=true
Keywords=game;mod;zenless;zone;zero;wuthering;waves;neverness;everness;
EOF

    cat > "$pkgdir/usr/bin/modlinq" << 'EOF'
#!/bin/bash
cd /opt/modlinq
exec ./modlinq "$@"
EOF

    chmod +x "$pkgdir/usr/bin/modlinq"
    chmod +x "$pkgdir/opt/modlinq/modlinq"

    if [ -f "LICENSE" ]; then
        install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    fi
}
