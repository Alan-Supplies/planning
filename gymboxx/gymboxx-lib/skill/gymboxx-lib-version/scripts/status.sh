#!/usr/bin/env bash
# gymboxx-lib 버전 현황 리포트 (읽기 전용 — git fetch 외에는 아무것도 바꾸지 않는다)
# 사용: bash status.sh [출력파일]   (생략하면 stdout)
set -uo pipefail

LIB_DIR=${LIB_DIR:-$HOME/workspace/supplies/gymboxx-lib}
APP_DIR=${APP_DIR:-$HOME/workspace/supplies/gymboxx-app-server}
PKG=@suppliesfitness/gymboxx-lib
OUT=${1:-/dev/stdout}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

G() { git -C "$LIB_DIR" "$@"; }
# X.Y.Z(-dev.N) → 정렬용 숫자 키 (정식 > 같은 base 의 prerelease)
vkey() { echo "$1" | awk -F'[.-]' '{ n = ($4=="dev") ? $5 : 99999; printf "%05d%05d%05d%05d\n", $1, $2, $3, n }'; }
base_of() { echo "${1%%-*}"; }
is_version_subject() { echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?$'; }
# 자기 커밋만 (머지·버전 범프 커밋 제외)
own_commits() {
  G log --no-merges --format='%h|%an|%s' "$1" | while IFS='|' read -r h a s; do
    is_version_subject "$s" || echo "    - \`$h\` $a — $s"
  done
}
# upstream 에 패치 동등물이 없는 HEAD 쪽 커밋만 (cherry-pick 된 것 제외)
unpicked_commits() {
  G cherry "$1" "$2" | awk '$1=="+"{print $2}' | while read -r sha; do
    s=$(G log -1 --format='%s' "$sha"); is_version_subject "$s" && continue
    echo "    - \`$(G log -1 --format='%h' "$sha")\` $(G log -1 --format='%an — %s' "$sha")"
  done
}

G fetch origin --tags --prune -q 2>/dev/null || echo "⚠️ lib fetch 실패 — 로컬 ref 기준" >&2
git -C "$APP_DIR" fetch origin main develop -q 2>/dev/null || echo "⚠️ app-server fetch 실패" >&2

G tag --list > "$TMP/tags"
grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' "$TMP/tags" > "$TMP/rel" || true

# main 에 올라간 정식 태그
G tag --merged origin/main | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n > "$TMP/main_rel_sorted"
MAIN_LATEST=$(tail -1 "$TMP/main_rel_sorted")
IFS=. read -r MX MY MZ <<< "$MAIN_LATEST"
LINE="$MX.$((MY + 1)).0"

# npm 발행 버전
if (cd "$LIB_DIR" && npm view "$PKG" versions --json 2>/dev/null) | tr -d ' ",[]' | grep -E '^[0-9]' > "$TMP/npm"; then NPM_OK=1; else NPM_OK=0; : > "$TMP/npm"; fi

# 원격 브랜치 package.json 버전
: > "$TMP/branch_ver"
for b in $(G branch -r --format='%(refname:short)' | grep -v -e HEAD -e '^origin$'); do
  v=$(G show "$b:package.json" 2>/dev/null | sed -n 's/^ *"version": *"\(.*\)".*/\1/p' | head -1)
  [ -n "$v" ] && echo "$v ${b#origin/}" >> "$TMP/branch_ver"
done

# VERSIONS.md — 브랜치마다 사본이 달라서 기준일이 가장 최신인 것을 읽는다 (작업 트리 포함)
VERSIONS_MD="$TMP/VERSIONS.md"; VMD_SRC=""; best=""
vmd_date() { sed -n 's/^기준일: *//p' | head -1; }
[ -f "$LIB_DIR/VERSIONS.md" ] && { best=$(vmd_date < "$LIB_DIR/VERSIONS.md"); VMD_SRC="작업 트리"; cp "$LIB_DIR/VERSIONS.md" "$VERSIONS_MD"; }
for b in $(G branch -r --format='%(refname:short)' | grep -v -e HEAD -e '^origin$'); do
  d=$(G show "$b:VERSIONS.md" 2>/dev/null | vmd_date)
  if [ -n "$d" ] && [ "$d" \> "$best" ]; then best=$d; VMD_SRC=$b; G show "$b:VERSIONS.md" > "$VERSIONS_MD"; fi
done
MAIN_VMD_DATE=$(G show origin/main:VERSIONS.md 2>/dev/null | vmd_date)
: > "$TMP/vmd"
[ -f "$VERSIONS_MD" ] && grep -E '^\| \**[0-9]+\.[0-9]+\.[0-9]+' "$VERSIONS_MD" \
  | awk -F'|' '{ v=$2; gsub(/[ *]/,"",v); s=$3; gsub(/^ +| +$/,"",s); print v "\t" s }' > "$TMP/vmd"

# 점유 번호 = 태그 ∪ npm ∪ 브랜치 package.json ∪ VERSIONS.md
{ cat "$TMP/tags" "$TMP/npm"; awk '{print $1}' "$TMP/branch_ver"; cut -f1 "$TMP/vmd"; } | sort -u > "$TMP/occupied"

# dev 라인
grep -E "^${LINE//./\\.}-dev\.[0-9]+$" "$TMP/tags" | awk -F'dev.' '{print $2, $0}' | sort -n | awk '{print $2}' > "$TMP/line_tags"
DEV_TIP=$(tail -1 "$TMP/line_tags")
MAX_N=$(grep -E "^${LINE//./\\.}-dev\.[0-9]+$" "$TMP/occupied" | awk -F'dev.' '{print $2}' | sort -n | tail -1)
NEXT_DEV="$LINE-dev.$(( ${MAX_N:--1} + 1 ))"

next_free() { # 점유되지 않은 다음 정식 번호
  local v=$1
  while grep -qx "$v" "$TMP/occupied"; do IFS=. read -r a b c <<< "$v"; v="$a.$b.$((c + 1))"; done
  echo "$v"
}
NEXT_PATCH=$(next_free "$MX.$MY.$((MZ + 1))")
NEXT_MINOR="$MX.$((MY + 1)).0"

{
echo "# gymboxx-lib 버전 현황 ($(date '+%Y-%m-%d %H:%M'))"
echo
echo "## 요약"
echo "- main 최신 정식: \`$MAIN_LATEST\`"
echo "- dev 라인: \`$LINE-dev.*\` · 팁 \`${DEV_TIP:-없음}\` · 다음 dev 번호 \`$NEXT_DEV\`"
echo "- 다음 main 번호: patch \`$NEXT_PATCH\` / minor \`$NEXT_MINOR\`$( [ -n "$DEV_TIP" ] && echo " (minor 를 main 이 가져가면 dev 라인은 \`$MX.$((MY + 2)).0-dev.0\` 으로 넘어간다)")"
[ "$NPM_OK" = 1 ] || echo "- ⚠️ npm 조회 실패 — 점유 번호에 npm 이 빠졌다 (\`npm view $PKG versions\` 인증 확인)"
echo

echo "## 1. main 정식 발행 (최근 3개)"
tail -3 "$TMP/main_rel_sorted" | sort -r | while read -r t; do echo "- \`$t\` $(G log -1 --format='%an %cs' "$t")"; done
UNMERGED_REL=$(comm -23 <(sort "$TMP/rel") <(sort "$TMP/main_rel_sorted") | while read -r t; do
  [ "$(vkey "$t")" \> "$(vkey "$MAIN_LATEST")" ] && echo "$t"; done)
[ -n "$UNMERGED_REL" ] && echo "- ⚠️ main 에 없는데 main 최신보다 큰 정식 태그: $(echo $UNMERGED_REL | sed 's/ /, /g')"
echo

echo "## 2. dev 라인 \`$LINE-dev.*\`"
if [ -z "$DEV_TIP" ]; then
  echo "- 태그 없음. 첫 dev 는 origin/main 위에서 \`$LINE-dev.0\`."
else
  prev=$(G describe --tags --abbrev=0 "$(head -1 "$TMP/line_tags")^" 2>/dev/null)
  [ -n "$prev" ] && echo "- 라인 시작점: \`$prev\` 위"
  while read -r t; do
    br=$(G branch -r --contains "$t" --format='%(refname:short)' | sed 's#^origin/##' | grep -v '^HEAD' | tr '\n' ' ')
    echo "- \`$t\` $(G log -1 --format='%an %cs' "$t") · 포함 브랜치: ${br:-없음}"
    if [ -n "$prev" ]; then own_commits "$prev..$t"; fi
    prev=$t
  done < "$TMP/line_tags"
fi
OTHER_LINES=$(grep -E -- '-dev\.[0-9]+$' "$TMP/tags" | while read -r t; do
  [ "$(vkey "$(base_of "$t")")" \> "$(vkey "$LINE")" ] && base_of "$t"; done | sort -u | tr '\n' ' ')
[ -n "$OTHER_LINES" ] && echo "- ⚠️ 라인보다 앞선 prerelease 가 있다: $OTHER_LINES"
echo

echo "## 3. dev 팁에 없는 main 커밋"
if [ -n "$DEV_TIP" ]; then
  MB=$(G merge-base "$DEV_TIP" origin/main)
  echo "- 분기점: \`$(G log -1 --format='%h %s' "$MB")\`"
  missing=0
  while read -r sign sha; do
    [ "$sign" = "+" ] || continue
    s=$(G log -1 --format='%s' "$sha"); is_version_subject "$s" && continue
    rel=$(G tag --contains "$sha" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | while read -r t; do echo "$(vkey "$t") $t"; done | sort | head -1 | awk '{print $2}')
    echo "  - \`$(G log -1 --format='%h' "$sha")\` [${rel:-미발행}] $(G log -1 --format='%an — %s' "$sha")"
    missing=$((missing + 1))
  done < <(G cherry "$DEV_TIP" origin/main "$MB")
  [ "$missing" = 0 ] && echo "- 없음. dev 팁이 main 을 모두 담고 있다."
else
  echo "- dev 라인 없음"
fi
echo

echo "## 4. 소비처 (app-server)"
for b in main develop; do
  pin=$(git -C "$APP_DIR" show "origin/$b:package.json" 2>/dev/null | sed -n "s#.*\"$PKG\": *\"[\^~]*\([^\"]*\)\".*#\1#p")
  echo "- \`origin/$b\`: \`${pin:-조회 실패}\`"
  if [ "$b" = develop ] && [ -n "$pin" ] && [ -n "$DEV_TIP" ] && [ "$pin" != "$DEV_TIP" ]; then
    if grep -qx "$pin" "$TMP/tags" && G merge-base --is-ancestor "$pin" "$DEV_TIP" 2>/dev/null; then
      echo "  - develop 을 dev 팁 위 번호로 올리면 함께 들어오는 커밋 (\`$pin..$DEV_TIP\`):"
      own_commits "$pin..$DEV_TIP" | sed 's/^/  /'
    else
      echo "  - ⚠️ 핀 \`$pin\` 이 dev 팁 \`$DEV_TIP\` 의 조상이 아니다 — 다른 갈래를 쓰고 있다"
    fi
  fi
done
echo

echo "## 5. 점유 번호 (\`$MAIN_LATEST\` 초과)"
MK=$(vkey "$MAIN_LATEST")
while read -r v; do
  [ "$(vkey "$v")" \> "$MK" ] || continue
  src=""
  grep -qx "$v" "$TMP/tags" && src="$src tag"
  grep -qx "$v" "$TMP/npm" && src="$src npm"
  grep -q "^$v	" "$TMP/vmd" && src="$src VERSIONS.md"
  brs=$(awk -v v="$v" '$1==v {print $2}' "$TMP/branch_ver" | tr '\n' ' ')
  flag=""
  echo "$src" | grep -q tag || flag=" ⚠️ 태그 없이 예약만 됨"
  echo "- \`$v\`:${src}${brs:+ · 브랜치: $brs}$flag"
done < <(while read -r v; do echo "$(vkey "$v") $v"; done < "$TMP/occupied" | sort | awk '{print $2}')
echo

echo "## 6. VERSIONS.md 괴리"
if [ ! -s "$TMP/vmd" ]; then
  echo "- VERSIONS.md 표를 읽지 못했다"
else
  echo "- 읽은 사본: \`$VMD_SRC\` (기준일 $best) · origin/main 사본 기준일: ${MAIN_VMD_DATE:-없음}"
  # 최근 main 발행 3개 + main 최신 이후 번호만 본다 (옛 dev 태그는 이력이라 표에 없어도 된다)
  { tail -3 "$TMP/main_rel_sorted"; sort -u "$TMP/tags" "$TMP/npm" | while read -r v; do
      [ "$(vkey "$v")" \> "$(vkey "$MAIN_LATEST")" ] && echo "$v"; done; } | sort -u | while read -r v; do
    grep -q "^$v	" "$TMP/vmd" || echo "  - 표에 없음: \`$v\`$(grep -qx "$v" "$TMP/main_rel_sorted" && echo ' (main 발행)')"
  done
  while IFS="$(printf '\t')" read -r v s; do
    on_main=0; grep -qx "$v" "$TMP/main_rel_sorted" && on_main=1
    published=0; { grep -qx "$v" "$TMP/tags" || grep -qx "$v" "$TMP/npm"; } && published=1
    if [ $on_main = 1 ] && ! echo "$s" | grep -q '✅'; then echo "  - 상태 갱신: \`$v\` 는 main 발행됨 (표: $s)"; fi
    if echo "$s" | grep -q '✅' && [ $on_main = 0 ]; then echo "  - 상태 확인: \`$v\` 가 ✅ 인데 main 태그가 아니다"; fi
    if echo "$s" | grep -q '미발행' && [ $published = 1 ]; then echo "  - 상태 갱신: \`$v\` 는 발행됐다 (표: $s)"; fi
  done < "$TMP/vmd"
fi
echo

echo "## 7. 로컬 작업 브랜치"
cur=$(G branch --show-current)
echo "- \`$cur\` · package.json \`$(sed -n 's/^ *"version": *"\(.*\)".*/\1/p' "$LIB_DIR/package.json" | head -1)\` · 변경 $(G status --porcelain | wc -l | tr -d ' ')건"
echo "- origin/main 에 없는 커밋 (cherry 기준):"; unpicked_commits origin/main HEAD | head -15
[ -n "$DEV_TIP" ] && { echo "- dev 팁 \`$DEV_TIP\` 에 없는 커밋 (cherry 기준):"; unpicked_commits "$DEV_TIP" HEAD | head -15; }
} > "$OUT"
