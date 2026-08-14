# Maintainer: NotionMe <c.ubohyi.stanislav@student.uzhnu.edu.ua>
pkgname=modlinq-git
pkgver=r6.967f969
pkgrel=1
pkgdesc="Mod manager for Zenless Zone Zero, Wuthering Waves and Neverness to Everness"
arch=('x86_64')
url="https://github.com/NotionMe/Mod-manager"
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
source=("git+https://github.com/NotionMe/Mod-manager.git")
sha256sums=('SKIP')

pkgver() {
    cd "$srcdir/Mod-manager"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

prepare() {
    cd "$srcdir/Mod-manager/modlinq"
    
    # Встановлюємо Flutter залежності
    export PUB_CACHE="$srcdir/pub_cache"
    flutter pub get
}

build() {
    cd "$srcdir/Mod-manager/modlinq"
    
    # Експортуємо Flutter cache
    export PUB_CACHE="$srcdir/pub_cache"
    
    # Будуємо Flutter додаток для Linux
    flutter build linux --release
}

package() {
    cd "$srcdir/Mod-manager"
    
    # Створюємо директорії
    install -dm755 "$pkgdir/opt/modlinq"
    install -dm755 "$pkgdir/usr/bin"
    install -dm755 "$pkgdir/usr/share/applications"
    install -dm755 "$pkgdir/usr/share/pixmaps"
    install -dm755 "$pkgdir/usr/share/icons/hicolor/256x256/apps"
    
    # Копіюємо Flutter build
    cp -r modlinq/build/linux/x64/release/bundle/* "$pkgdir/opt/modlinq/"
    
    # Копіюємо іконку
    if [ -f "assets/icon.png" ]; then
        install -Dm644 assets/icon.png "$pkgdir/opt/modlinq/data/flutter_assets/assets/icon.png"
        install -Dm644 assets/icon.png "$pkgdir/usr/share/pixmaps/modlinq.png"
        install -Dm644 assets/icon.png "$pkgdir/usr/share/icons/hicolor/256x256/apps/modlinq.png"
    fi
    
    # Примітка: mod_images тепер зберігаються в ~/.local/share/modlinq/mod_images
    # Директорія буде створена автоматично при першому запуску застосунку
    
    # Створюємо .desktop файл
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
Keywords=game;mod;zenless;zone;zero;
EOF
    
    # Створюємо wrapper скрипт для легкого запуску
    cat > "$pkgdir/usr/bin/modlinq" << 'EOF'
#!/bin/bash
cd /opt/modlinq
exec ./modlinq "$@"
EOF
    
    chmod +x "$pkgdir/usr/bin/modlinq"
    
    # Встановлюємо права на виконання
    chmod +x "$pkgdir/opt/modlinq/modlinq"
    
    # Копіюємо документацію якщо є
    if [ -f "AUR_GUIDE.md" ]; then
        install -Dm644 AUR_GUIDE.md "$pkgdir/usr/share/doc/modlinq/AUR_GUIDE.md"
    fi
    if [ -f "FLATPAK_GUIDE.md" ]; then
        install -Dm644 FLATPAK_GUIDE.md "$pkgdir/usr/share/doc/modlinq/FLATPAK_GUIDE.md"
    fi
    
    # Копіюємо ліцензію якщо є
    if [ -f "LICENSE" ]; then
        install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    fi
}
