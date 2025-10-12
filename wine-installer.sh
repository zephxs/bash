#!/bin/bash
#NOTE: Can only run on aarch64 (since box64 can only run on aarch64)
# box64 runs wine-amd64, box86 runs wine-i386.
### User-defined Wine version variables ################
# - Replace the variables below with your system's info.
# - Note that we need the amd64 version for Box64 even though we're installing it on our ARM processor.
# - Note that we need the i386 version for Box86 even though we're installing it on our ARM processor.
# - Wine download links from WineHQ: https://dl.winehq.org/wine-builds/

_WKGDIR="$HOME/wine-pkgs"
[ -d "$_WKGDIR" ] || mkdir -p "$_WKGDIR"
cd "$_WKGDIR"

_USAGE(){
echo "Usage:
  -b | --branch        # ex: stable, staging, devel
  -v | --version       # Ex: 8.1
  -s | --symlink       # Apply symplink to selected version
  -l | --list          # This help
  -h | --help          # This help
"
}

# Param get
while (($#)); do
  case $1 in
    -b|--branch) branch="$2"; shift 2 ;;
    -v|--version) version="$2"; shift 2 ;;
    -s|--links) _LINK="true"; shift 1 ;;
    -l|--list) _LISTONLY="true"; shift 1 ;;
    -h|--help) _USAGE && exit 0 ;;
    *) _USAGE; exit 1 ;;
  esac
done
  
[ -z "$branch" ] && branch="staging" #example: devel, staging, or stable (wine-staging 4.5+ requires libfaudio0:i386)
[ -z "$version" ] && version="9.4" #example: "7.1"
id="ubuntu" #example: debian, ubuntu
dist="jammy" #example (for debian): bullseye, buster, jessie, wheezy, ${VERSION_CODENAME}, etc 
tag="-1" #example: -1 (some wine .deb files have -1 tag on the end and some don't)
LNKA="https://dl.winehq.org/wine-builds/${id}/dists/${dist}/main/binary-amd64/" #amd64-wine links
LNKB="https://dl.winehq.org/wine-builds/${id}/dists/${dist}/main/binary-i386/" #i386-wine links

echo "### Wine Installer ###
  OS      = $id
  Distro  = $dist
  Branch  = $branch
  Version = $version
"

### FUNCTIONS
_YESNO(){
echo "Continue ? [Y/n]"
read -s -n1
echo
case $REPLY in
  y|Y) ;;
  *) echo -e "OKThxBye!\n"; exit 0 ;;
esac
}

_LIST_REPO(){
echo "# LIST AVAILABLE PACKAGES"
curl -s --list-only -L "$LNKB" |awk -F'"winehq-|">' '/winehq/ {print $4}'
echo
exit 0
}

_DEB_INSTALL(){
echo "# INSTALL WINE"
[ -d "/usr/share/wine_versions" ] || mkdir -p /usr/share/wine_versions
[ -d "/usr/share/wine_versions/wine-${branch}-${version}" ] && echo "Already in place: /usr/share/wine_versions/wine-${branch}-${version}"
_YESNO
[ -d "/usr/share/wine_versions/wine-${branch}-${version}" ] && rm -rf "/usr/share/wine_versions/wine-${branch}-${version}"
# Wine download links from WineHQ: https://dl.winehq.org/wine-builds/
DEB_A1="wine-${branch}-amd64_${version}~${dist}${tag}_amd64.deb" #wine64 main bin
DEB_A2="wine-${branch}_${version}~${dist}${tag}_amd64.deb" #wine64 support files (required for wine64 / can work alongside wine_i386 main bin)
#DEB_A3="winehq-${branch}_${version}~${dist}${tag}_amd64.deb" #shortcuts & docs
DEB_B1="wine-${branch}-i386_${version}~${dist}${tag}_i386.deb" #wine_i386 main bin
DEB_B2="wine-${branch}_${version}~${dist}${tag}_i386.deb" #wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files)
#DEB_B3="winehq-${branch}_${version}~${dist}${tag}_i386.deb" #shortcuts & docs

# Install amd64-wine (64-bit) alongside i386-wine (32-bit)
echo -e "Downloading wine..."
wget -q ${LNKA}${DEB_A1} 
wget -q ${LNKA}${DEB_A2} 
wget -q ${LNKB}${DEB_B1} 
[ -f "$DEB_A1" -a -f "$DEB_A2" -a -f "$DEB_B1" ] || { echo "Not all deb packages are available.. Exit" && exit 1; }
echo -e "Extracting wine..."
dpkg-deb -x ${DEB_A1} wine-installer
dpkg-deb -x ${DEB_A2} wine-installer
dpkg-deb -x ${DEB_B1} wine-installer
echo -e "Installing wine..."
mv ${_WKGDIR}/wine-installer/opt/wine* /usr/share/wine_versions/wine-${branch}-${version}
rm -f ${_WKGDIR}/wine-*.deb
rm -rf ${_WKGDIR}/wine-installer/*
echo "Installed in /usr/share/wine_versions/wine-${branch}-${version}"
echo
}

_LINK_WINE(){
echo "# WINE SYMLINKS"
_YESNO
[ -d "/usr/share/wine_versions/wine-${branch}-${version}" ] || { echo "Folder Not Found: /usr/share/wine_versions/wine-${branch}-${version}"; exit 1; }
if [ -h "/usr/local/bin/wineserver" ]; then
  echo "Remove old links..."
  for _WINELINK in /usr/local/bin/wine* ; do sudo unlink $_WINELINK; done
  #[ -f "/usr/local/bin/wine" ] && rm /usr/local/bin/wine
fi
echo "Linking Wine Binaries..."
cd /usr/share/wine_versions/wine-${branch}-${version}/bin/
  for _WINEBIN in wine* ; do
    sudo ln -s /usr/share/wine_versions/wine-${branch}-${version}/bin/$_WINEBIN /usr/local/bin/
  done
#[ -h "/usr/local/bin/wine" ] && sudo unlink /usr/local/bin/wine
#echo -e '#!/bin/bash\nsetarch linux32 -L '"/usr/share/wine_versions/wine-${branch}-${version}/bin/wine "'"$@"' | sudo tee /usr/local/bin/wine >/dev/null
#sudo chmod 755 /usr/local/bin/wine
if type -p wine >/dev/null; then
  echo "Wine is available in PATH: $(type -p wine) !"
else
  echo "Faile to Symlink Wine binaries"
fi
echo
}

[ "$_LISTONLY" = "true" ] && _LIST_REPO
[ "$_LINK" = "true" ] && _LINK_WINE || { _DEB_INSTALL; _LINK_WINE; }

