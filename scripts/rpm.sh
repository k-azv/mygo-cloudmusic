#!/usr/bin/env bash
# Packages a Linux build of mygo as an RPM, for Fedora, RHEL and openSUSE,
# from the Debian package that mygo build writes next to it: the same app in
# /opt/mygo-cloudmusic, its entry in the applications menu, and its icons.
#
#   scripts/rpm.sh build/linux-amd64/mygo-cloudmusic_0.1.25_amd64.deb x86_64 build/linux-amd64
#
# The RPM architecture is x86_64 for amd64 and aarch64 for arm64; the
# Debian package names its own. The name, version and description come from
# mygo.json. Needs rpmbuild, jq and ar or dpkg-deb.
set -euo pipefail

usage() {
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ $# -ne 3 ]]; then
	usage >&2
	exit 2
fi
deb=$1 arch=$2 out=$3
if [[ ! -f $deb ]]; then
	echo "scripts/rpm.sh: no such package: $deb" >&2
	exit 2
fi
if [[ $arch != x86_64 && $arch != aarch64 ]]; then
	echo "scripts/rpm.sh: unsupported architecture: $arch" >&2
	exit 2
fi
if ! command -v rpmbuild >/dev/null; then
	echo "scripts/rpm.sh: rpmbuild is needed: dnf install rpm-build, or apt-get install rpm" >&2
	exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
name=$(jq -r .slug "$root/mygo.json")
version=$(jq -r .version "$root/mygo.json")
comment=$(jq -r '.linux.comment // .name' "$root/mygo.json")
title=$(jq -r .name "$root/mygo.json")
version=${version#v}
# RPM has no "-" in a version: a pre-release sorts before its release
# with "~", as Debian spells it too.
version=$(printf "%s" "$version" | tr "-" "~")
nameRe='^[A-Za-z0-9][A-Za-z0-9._+-]*$'
versionRe='^[A-Za-z0-9][A-Za-z0-9._+~^]*$'
[[ $name =~ $nameRe ]] || { echo "scripts/rpm.sh: bad name: $name" >&2; exit 1; }
[[ $version =~ $versionRe ]] || { echo "scripts/rpm.sh: bad version: $version" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Unpack the app as the Debian package lays it out: opt/<name>, its entry
# and its icons, which desktops look for under their own paths.
mkdir -p "$work/payload"
deb=$(cd "$(dirname "$deb")" && pwd)/$(basename "$deb")
if command -v dpkg-deb >/dev/null; then
	dpkg-deb -x "$deb" "$work/payload"
else
	(cd "$work" && ar x "$deb" data.tar.*)
	tar -xf "$work"/data.tar.* -C "$work/payload"
	rm -f "$work"/data.tar.*
fi
[[ -x $work/payload/opt/$name/$name ]] || { echo "scripts/rpm.sh: $deb holds no /opt/$name/$name" >&2; exit 1; }

mkdir -p "$work/topdir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp -a "$work/payload" "$work/topdir/SOURCES/payload"
cp "$root/LICENSE" "$work/topdir/SOURCES/LICENSE"

# The app loads GTK, GDK, GLib and gdk-pixbuf with dlopen, which RPM does
# not see, so the package requires GTK itself. The tray icon is optional:
# without libayatana-appindicator3 the app runs without one.
cat > "$work/topdir/SPECS/$name.spec" <<EOF
Name:           $name
Version:        $version
Release:        1
Summary:        $comment
License:        AGPL-3.0-only
URL:            https://github.com/egoist/mygo-cloudmusic
AutoReqProv:    yes

Requires:       gtk3
Recommends:     libayatana-appindicator3.so.1()(64bit)

%global __os_install_post %{nil}
%global debug_package %{nil}

%description
$comment（$title），原生界面，无 WebView。

%install
mkdir -p %{buildroot}
cp -a %{_sourcedir}/payload/. %{buildroot}/
install -Dm644 %{_sourcedir}/LICENSE %{buildroot}/usr/share/licenses/$name/LICENSE

%post
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true

%postun
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true

%files
/opt/$name
/usr/share/applications/$name.desktop
/usr/share/icons/hicolor/256x256/apps/$name.png
/usr/share/icons/hicolor/512x512/apps/$name.png
%license /usr/share/licenses/$name/LICENSE

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') $title <noreply@github.com> - $version-1
- Built from the mygo build of $version.
EOF

rpmbuild --define "_topdir $work/topdir" --define "_build_id_links none" \
	--target "$arch" -bb "$work/topdir/SPECS/$name.spec" >&2

mkdir -p "$out"
rpm=$(ls "$work/topdir/RPMS/$arch/"*.rpm)
cp "$rpm" "$out/"
echo "$out/$(basename "$rpm")"
