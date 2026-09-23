#!/usr/bin/env bash
#
# detect_java.sh - Inventaire Java pour RHEL / Oracle Linux 7..10
#
# Détecte :
#   - tous les binaires java installés + leur version (et JDK si javac présent)
#   - le java lancé par défaut
#   - si le java par défaut est géré par alternatives (et la liste des candidats)
#   - les packages RPM liés à java
#
# Usage: ./detect_java.sh
# Prérequis: bash, rpm (distribution RPM), alternatives (ou update-alternatives)
# Ne nécessite pas root. Modifie rien sur la machine.
#
set -u

# ---------------------------------------------------------------- helpers
have() { command -v "$1" >/dev/null 2>&1; }

# extrait la version de la ligne "openjdk version "1.8.0_392"" etc.
get_java_version() {
    local bin="$1"
    "$bin" -version 2>&1 | head -n 1 | sed -n 's/.*"\([^"]*\)".*/\1/p'
}

# "openjdk", "java" ... depuis la 1re ligne de -version
get_vendor_hint() {
    local bin="$1"
    "$bin" -version 2>&1 | head -n 1 | awk '{print $1}'
}

# ---------------------------------------------------------------- collecte
# tous les binaires java trouvés (chemins bruts, doublons possibles)
candidates=""

# 1) java dans le PATH (tous) - type -a est un builtin bash, plus portable que which -a
candidates="$candidates $(type -a java 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')"

# 2) répertoires standards des JVM
for dir in /usr/lib/jvm /usr/java /usr/local/java /usr/local/jdk* /opt; do
    [ -d "$dir" ] || continue
    # maxdepth pour rester rapide, -xdev pour ne pas traverser les mounts
    candidates="$candidates $(find -L "$dir" -maxdepth 5 -type f -name java -perm -u+x 2>/dev/null)"
done

# 3) liens alternatives (si l'outil existe, la cible du lien est déjà
#    couverte par which -a, mais on la re-liste proprement)
if have alternatives; then
    ALT_TOOL=alternatives
elif have update-alternatives; then
    ALT_TOOL=update-alternatives
else
    ALT_TOOL=""
fi

# dédoublonnage + résolution des symlinks
resolved=$(for p in $candidates; do readlink -f "$p" 2>/dev/null; done | sort -u)

# ---------------------------------------------------------------- rapport
echo "=== Inventaire Java - $(hostname) - $(date '+%F %T') ==="
echo

# --- packages RPM java
echo "--- Packages RPM (jdk/jre/java/jdbc) ---"
if have rpm; then
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null \
        | grep -Ei '(jdk|jre|java|jdbc)' | sort || echo "(aucun)"
else
    echo "(rpm non disponible)"
fi
echo

# --- alternatives
if [ -n "$ALT_TOOL" ]; then
    echo "--- Alternatives (lien 'java') ---"
    if "$ALT_TOOL" --display java >/dev/null 2>&1; then
        # on retire les lignes indentées (slaves) pour rester lisible
        "$ALT_TOOL" --display java | grep -v '^[[:space:]]' | grep -v '^$'
    else
        echo "(pas d'entrée 'java' dans alternatives)"
    fi
else
    echo "--- Alternatives ---"
    echo "(outil alternatives absent)"
fi
echo

# --- JAVA_HOME
if [ -n "${JAVA_HOME:-}" ]; then
    echo "JAVA_HOME: $JAVA_HOME"
else
    echo "JAVA_HOME: (non défini)"
fi
echo

# --- java par défaut
default_bin=$(command -v java 2>/dev/null || true)
echo "--- Java par défaut ---"
if [ -n "$default_bin" ]; then
    echo "command:  java -> $default_bin"
    echo "réel:     $(readlink -f "$default_bin")"
    echo "version:  $(get_java_version "$default_bin")"
    # géré par alternatives ?
    if [ -n "$ALT_TOOL" ] && "$ALT_TOOL" --display java 2>/dev/null | grep -q .; then
        echo "alternatives: OUI (le lien /usr/bin/java est géré par $ALT_TOOL)"
    else
        echo "alternatives: NON (lien manuel ou hors alternatives)"
    fi
else
    echo "(aucun 'java' dans le PATH)"
fi
echo

# --- toutes les JVMs détectées
echo "--- JVMs détectées ---"
if [ -z "$resolved" ]; then
    echo "(aucune)"
else
    for bin in $resolved; do
        ver=$(get_java_version "$bin")
        vend=$(get_vendor_hint "$bin")
        kind="JRE"
        [ -x "$(dirname "$bin")/javac" ] && kind="JDK"
        # package RPM propriétaire ce binaire ?
        pkg=$(rpm -qf "$bin" --qf '%{NAME}-%{VERSION}' 2>/dev/null | grep -v 'non possédé' || true)
        printf '%-55s %-8s %-6s %s\n' "$bin" "${ver:-?}" "$kind" "${vend:-?}"
        [ -n "$pkg" ] && echo "    package: $pkg"
    done
fi
echo
echo "=== fin ==="