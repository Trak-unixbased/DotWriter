#!/usr/bin/env bash
# =============================================================================
#  build-dotwriter-deb.sh
#  Construit un paquet .deb de https://github.com/hailo-ai/DotWriter
#  conçu pour ne JAMAIS entrer en conflit avec un autre paquet, aujourd'hui
#  comme demain :
#
#   - nom de paquet dédié          : libdotwriter-hailo-dev  (aucun équivalent
#                                    Debian/Ubuntu/Hailo à ce jour, vérifié
#                                    automatiquement avant construction)
#   - en-têtes namespacés          : /usr/include/dotwriter-hailo/*.h
#                                    (l'install upstream autotools pose Node.h,
#                                    Edge.h, Graph.h, Util.h... directement dans
#                                    /usr/include -> collision quasi certaine)
#   - bibliothèque namespacée      : /usr/lib/<triplet>/dotwriter-hailo/libdotwriter.a
#   - pkg-config / CMake namespacés: dotwriter-hailo.pc, DotWriterHailoConfig.cmake
#   - statique uniquement (PIC)    : pas de .so, donc pas de SONAME à gérer ni
#                                    de collision ABI ; liable dans une .so
#   - commit figé + vérifié        : build reproductible (SOURCE_DATE_EPOCH)
#   - aucun Conflicts/Replaces     : coexistence possible avec un futur
#                                    libdotwriter-dev officiel (zéro fichier commun)
#
#  Usage : ./build-dotwriter-deb.sh [--skip-apt-check] [--keep-workdir]
#  Prérequis : git cmake g++ make dpkg-dev pkg-config  (lintian optionnel)
# =============================================================================
set -Eeuo pipefail
umask 022

# ------------------------------- Paramètres ----------------------------------
REPO_URL="https://github.com/hailo-ai/DotWriter.git"
COMMIT="e5fa8f281adca10dd342b1d32e981499b8681daf"   # HEAD master au 2022-01-10
UPSTREAM_VERSION="0.01"                             # cf. configure.ac / tag v0.01
COMMIT_DATE="20220110"
DEB_REVISION="1"

NS="dotwriter-hailo"                                # espace de nommage des chemins
PKG_NAME="libdotwriter-hailo-dev"
PKG_VERSION="${UPSTREAM_VERSION}+git${COMMIT_DATE}.${COMMIT:0:7}-${DEB_REVISION}"
MAINTAINER="${DEBFULLNAME:-Local Builder} <${DEBEMAIL:-root@localhost}>"

OUT_DIR="${OUT_DIR:-$PWD}"
SKIP_APT_CHECK=0
KEEP_WORKDIR=0
for arg in "$@"; do
  case "$arg" in
    --skip-apt-check) SKIP_APT_CHECK=1 ;;
    --keep-workdir)   KEEP_WORKDIR=1 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------- Prérequis -----------------------------------
for bin in git cmake g++ make strip objcopy dpkg-deb dpkg-architecture dpkg-buildflags pkg-config gzip; do
  command -v "$bin" >/dev/null 2>&1 || die "Outil manquant : $bin  (apt install git cmake g++ make dpkg-dev pkg-config)"
done

ARCH="$(dpkg-architecture -qDEB_HOST_ARCH)"
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
LIBDIR="/usr/lib/${MULTIARCH}"
DEB_FILE="${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}_${ARCH}.deb"

WORKDIR="$(mktemp -d -t dotwriter-deb.XXXXXX)"
cleanup() { [[ $KEEP_WORKDIR -eq 1 ]] && log "Répertoire de travail conservé : $WORKDIR" || rm -rf "$WORKDIR"; }
trap cleanup EXIT

SRC="$WORKDIR/src"; BUILD="$WORKDIR/build"; ROOT="$WORKDIR/pkgroot"

# Liste exhaustive des chemins livrés (sert aussi aux contrôles de conflit)
INCDIR="/usr/include/${NS}"
LIBSUBDIR="${LIBDIR}/${NS}"
PCFILE="${LIBDIR}/pkgconfig/${NS}.pc"
CMAKEDIR="${LIBDIR}/cmake/DotWriterHailo"
DOCDIR="/usr/share/doc/${PKG_NAME}"

# --------------------- 1. Contrôles de conflit (avant build) -----------------
log "Contrôle d'unicité du nom de paquet et des chemins"
if dpkg-query -W -f='${Status}\n' "$PKG_NAME" 2>/dev/null | grep -q '^install ok installed'; then
  INSTALLED_VER="$(dpkg-query -W -f='${Version}' "$PKG_NAME")"
  warn "$PKG_NAME $INSTALLED_VER est déjà installé (sera mis à jour/remplacé par ce build)."
fi

if [[ $SKIP_APT_CHECK -eq 0 ]] && command -v apt-cache >/dev/null 2>&1; then
  if apt-cache show "$PKG_NAME" 2>/dev/null | grep -q '^Package:'; then
    origin="$(apt-cache policy "$PKG_NAME" | sed -n '/Version table/,$p' | grep -v '/var/lib/dpkg/status' | grep -E 'http|file:' | head -1 || true)"
    [[ -n "$origin" ]] && die "Un paquet '$PKG_NAME' existe déjà dans un dépôt APT configuré ($origin). Changez PKG_NAME/NS."
  fi
fi

for p in "$INCDIR" "$LIBSUBDIR" "$PCFILE" "$CMAKEDIR"; do
  if owner="$(dpkg -S "$p" 2>/dev/null)"; then
    echo "$owner" | grep -q "^${PKG_NAME}:" || die "Chemin déjà possédé par un autre paquet : $owner"
  fi
done
if [[ $SKIP_APT_CHECK -eq 0 ]] && command -v apt-file >/dev/null 2>&1; then
  for p in "$INCDIR/" "$LIBSUBDIR/" "$PCFILE" "$CMAKEDIR/"; do
    hits="$(apt-file search -x "^${p//./\\.}" 2>/dev/null | grep -v "^${PKG_NAME}:" || true)"
    [[ -n "$hits" ]] && die "Chemin fourni par un paquet des dépôts : $hits"
  done
else
  [[ $SKIP_APT_CHECK -eq 0 ]] && warn "apt-file absent : vérification des dépôts limitée au nom de paquet (apt install apt-file && apt-file update pour un contrôle complet)."
fi

# --------------------------- 2. Récupération des sources ---------------------
log "Clonage de $REPO_URL @ ${COMMIT:0:12}"
git init -q "$SRC"
git -C "$SRC" remote add origin "$REPO_URL"
git -C "$SRC" fetch -q --depth 1 origin "$COMMIT" \
  || git -C "$SRC" fetch -q origin   # repli si le serveur refuse le fetch par SHA
git -C "$SRC" -c advice.detachedHead=false checkout -q "$COMMIT"
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$COMMIT" ]] || die "Commit inattendu après checkout"

export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH="$(git -C "$SRC" log -1 --format=%ct)"
export TZ=UTC LC_ALL=C

# --------------------------------- 3. Build ----------------------------------
log "Compilation (statique, PIC, durcissement dpkg-buildflags, sans LTO)"
# LTO désactivé : une archive .a contenant du bytecode LTO est liée à la version
# exacte de GCC et casserait l'édition de liens après une montée de version du
# compilateur (conflit "ultérieur" typique).
CXXFLAGS="$(DEB_BUILD_MAINT_OPTIONS='hardening=+all optimize=-lto' dpkg-buildflags --get CXXFLAGS) -ffile-prefix-map=${SRC}=."
CPPFLAGS="$(DEB_BUILD_MAINT_OPTIONS='hardening=+all optimize=-lto' dpkg-buildflags --get CPPFLAGS)"
# CMAKE_POLICY_VERSION_MINIMUM : le CMakeLists upstream déclare 3.0, rejeté par CMake >= 4
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_CXX_FLAGS="$CPPFLAGS $CXXFLAGS" \
  -Wno-deprecated >/dev/null
cmake --build "$BUILD" --parallel "$(nproc)" >/dev/null
LIB_A="$(find "$BUILD" -name 'libdotwriter.a' -print -quit)"
[[ -f "$LIB_A" ]] || die "libdotwriter.a introuvable après compilation"
# Retrait des symboles de débogage (14 Mo -> quelques centaines de Ko) + archive
# déterministe (horodatages/uid neutralisés). Mettre KEEP_DEBUG=1 pour les garder.
if [[ "${KEEP_DEBUG:-0}" != "1" ]]; then
  strip --strip-debug --enable-deterministic-archives "$LIB_A"
else
  objcopy --enable-deterministic-archives "$LIB_A"
fi

# ------------------- 4. Arborescence du paquet (install manuelle) ------------
# On n'utilise PAS 'make install' / 'cmake --install' :
#  - autotools : en-têtes génériques directement dans /usr/include + .so sans SONAME versionné
#  - CMake     : n'installe que DotWriter.h (inutilisable seul) et l'archive dans ./build/
log "Préparation de l'arborescence"
install -d -m 0755 "$ROOT/DEBIAN" "$ROOT$INCDIR" "$ROOT$LIBSUBDIR" \
                   "$ROOT${LIBDIR}/pkgconfig" "$ROOT$CMAKEDIR" "$ROOT$DOCDIR"

install -m 0644 "$SRC"/lib/*.h "$ROOT$INCDIR/"
install -m 0644 "$LIB_A"       "$ROOT$LIBSUBDIR/libdotwriter.a"

cat > "$ROOT$PCFILE" <<EOF
prefix=/usr
libdir=\${prefix}/lib/${MULTIARCH}/${NS}
includedir=\${prefix}/include/${NS}

Name: DotWriter (Hailo fork)
Description: C++ API for generating GraphViz DOT files (static, hailo-ai fork)
Version: ${UPSTREAM_VERSION}+git${COMMIT_DATE}
Cflags: -I\${includedir}
Libs: -L\${libdir} -ldotwriter
EOF

cat > "$ROOT$CMAKEDIR/DotWriterHailoConfig.cmake" <<EOF
# Fourni par ${PKG_NAME} ${PKG_VERSION}
# Usage : find_package(DotWriterHailo REQUIRED)
#         target_link_libraries(mon_projet PRIVATE DotWriterHailo::DotWriter)
if(NOT TARGET DotWriterHailo::DotWriter)
  add_library(DotWriterHailo::DotWriter STATIC IMPORTED)
  set_target_properties(DotWriterHailo::DotWriter PROPERTIES
    IMPORTED_LOCATION             "${LIBSUBDIR}/libdotwriter.a"
    INTERFACE_INCLUDE_DIRECTORIES "${INCDIR}"
    INTERFACE_COMPILE_FEATURES    "cxx_std_14")
endif()
set(DotWriterHailo_FOUND TRUE)
EOF
cat > "$ROOT$CMAKEDIR/DotWriterHailoConfigVersion.cmake" <<EOF
set(PACKAGE_VERSION "${UPSTREAM_VERSION}")
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
EOF
chmod 0644 "$ROOT$PCFILE" "$ROOT$CMAKEDIR"/*.cmake

# Documentation / licence (MIT)
cat > "$ROOT$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DotWriter
Source: ${REPO_URL%.git}
Comment: Fork hailo-ai de https://github.com/jvilk/DotWriter, commit ${COMMIT}

Files: *
Copyright: 2012 John Vilk
License: MIT
EOF
sed 's/^$/./; s/^/ /' "$SRC/LICENSE" >> "$ROOT$DOCDIR/copyright"
install -m 0644 "$SRC/README.md" "$ROOT$DOCDIR/README.md"
gzip -9n "$ROOT$DOCDIR/README.md"

CHANGELOG_DATE="$(date -u -R -d "@${SOURCE_DATE_EPOCH}")"
cat > "$WORKDIR/changelog.Debian" <<EOF
${PKG_NAME} (${PKG_VERSION}) unstable; urgency=medium

  * Paquet local construit depuis ${REPO_URL} @ ${COMMIT:0:12}.
  * En-têtes et bibliothèque namespacés sous '${NS}' pour éviter tout conflit.

 -- ${MAINTAINER}  ${CHANGELOG_DATE}
EOF
gzip -9nc "$WORKDIR/changelog.Debian" > "$ROOT$DOCDIR/changelog.Debian.gz"
chmod 0644 "$ROOT$DOCDIR"/*

# ------------------------------- 5. Contrôle ---------------------------------
INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Source: dotwriter-hailo
Version: ${PKG_VERSION}
Architecture: ${ARCH}
Multi-Arch: same
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: libstdc++-dev | libstdc++-14-dev | libstdc++-13-dev | libstdc++-12-dev
Suggests: graphviz, pkgconf | pkg-config
Section: libdevel
Priority: optional
Homepage: ${REPO_URL%.git}
Description: C++ API for generating GraphViz DOT files (hailo-ai fork, static)
 DotWriter lets C++ programs describe graphs (nodes, edges, subgraphs,
 clusters and their attributes) and emit them as DOT files for GraphViz.
 .
 This package ships the hailo-ai fork as a position-independent static
 library. All files live under the '${NS}' namespace so the package can
 coexist with any other DotWriter packaging:
  - headers   : ${INCDIR}/
  - library   : ${LIBSUBDIR}/libdotwriter.a
  - pkg-config: ${NS}
  - CMake     : find_package(DotWriterHailo) -> DotWriterHailo::DotWriter
EOF

( cd "$ROOT" && find usr -type f -print0 | sort -z | xargs -0 md5sum ) > "$ROOT/DEBIAN/md5sums"
chmod 0644 "$ROOT/DEBIAN/control" "$ROOT/DEBIAN/md5sums"
find "$ROOT" -type d -exec chmod 0755 {} +
find "$ROOT" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +

# ----------------------- 6. Test d'utilisation avant emballage ---------------
log "Test de compilation/édition de liens contre l'arborescence du paquet"
cat > "$WORKDIR/t.cpp" <<'EOF'
#include <DotWriter.h>
#include <sstream>
int main() {
  DotWriter::RootGraph g(false, "t");
  auto *a = g.AddNode("A"); auto *b = g.AddNode("B");
  g.AddEdge(a, b);
  std::ostringstream os; g.Print(os);
  return os.str().find("--") == std::string::npos;
}
EOF
g++ -std=c++14 -I"$ROOT$INCDIR" "$WORKDIR/t.cpp" -L"$ROOT$LIBSUBDIR" -ldotwriter -o "$WORKDIR/t"
"$WORKDIR/t" || die "Le binaire de test a échoué"

# ------------------------------ 7. Emballage ---------------------------------
log "Construction de $(basename "$DEB_FILE")"
mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$DEB_FILE" >/dev/null

# Vérification finale : aucun fichier livré n'est déjà possédé par un autre paquet
while read -r f; do
  if owner="$(dpkg -S "$f" 2>/dev/null)"; then
    echo "$owner" | grep -q "^${PKG_NAME}:" || die "Conflit détecté sur $f : $owner"
  fi
done < <(dpkg-deb -c "$DEB_FILE" | awk '$1 !~ /^d/ {sub(/^\./,"",$6); print $6}')

if command -v lintian >/dev/null 2>&1; then
  log "lintian"
  lintian --no-tag-display-limit "$DEB_FILE" || warn "lintian a signalé des remarques (non bloquant)"
fi

log "Paquet prêt : $DEB_FILE"
dpkg-deb -I "$DEB_FILE" | sed -n '/Package:/,/Homepage:/p'
echo
echo "Installation : sudo apt install ./$(basename "$DEB_FILE")"
echo "Compilation  : g++ -std=c++14 prog.cpp \$(pkg-config --cflags --libs ${NS})"
echo "CMake        : find_package(DotWriterHailo REQUIRED) + DotWriterHailo::DotWriter"
