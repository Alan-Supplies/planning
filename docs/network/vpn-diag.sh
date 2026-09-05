#!/bin/bash
# VPN 증상 발생 시점 스냅샷 — 증상이 난 "그 자리에서" 실행할 것
# 사용: bash planning/docs/network/vpn-diag.sh
# 결과: 화면 출력 + ~/Downloads/vpn-diag-<시각>.txt 저장

OUT="$HOME/Downloads/vpn-diag-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$OUT") 2>&1

echo "═══ VPN 진단 스냅샷 $(date '+%Y-%m-%d %H:%M:%S') ═══"

echo
echo "── 1. VPN 연결 상태 ──"
if ifconfig 2>/dev/null | grep -q "192.168.255"; then
  echo "VPN: 연결됨"
  ifconfig 2>/dev/null | grep -B4 "192.168.255" | grep -E "^utun|inet |mtu"
else
  echo "VPN: 미연결"
fi
echo "사내 라우트 수: $(netstat -rn -f inet 2>/dev/null | grep -cE '192\.168\.255')"
echo "기본 경로: $(netstat -rn -f inet 2>/dev/null | grep '^default' | head -1)"

echo
echo "── 2. DNS 설정 ──"
echo "[resolv.conf]"; grep nameserver /etc/resolv.conf 2>/dev/null
echo "[시스템 primary]"; scutil --dns 2>/dev/null | awk '/^resolver #1$/{f=1;next} f&&/nameserver/{print} f&&/^$/{exit}'
echo "[/etc/resolver] ($(ls /etc/resolver/ 2>/dev/null | wc -l | tr -d " ")개)"; ls /etc/resolver/ 2>/dev/null | tr "\n" " "; echo
[ -d /etc/resolver ] || echo "  (없음 — 정상)"

echo
echo "── 3. 이름 해석 (경로별 비교) ──"
for h in github.com vpn.supp.fitness db.gymboxx.dev.supp.kr; do
  echo "[$h]"
  printf "  dig 시스템    : %s\n" "$(dig $h +short +timeout=3 +tries=1 2>&1 | tail -1)"
  printf "  dig 사내DNS   : %s\n" "$(dig $h +short +timeout=3 +tries=1 @10.0.0.2 2>&1 | tail -1)"
  printf "  dig 공용DNS   : %s\n" "$(dig $h +short +timeout=3 +tries=1 @1.1.1.1 2>&1 | tail -1)"
  # 앱이 실제로 쓰는 경로. dig 와 다르면 /etc/resolver 문제
  s=$(date +%s)
  a=$( perl -e "alarm 12; exec @ARGV" dscacheutil -q host -a name $h 2>/dev/null | grep -m1 ip_address )
  printf "  dscacheutil   : %s (%ss)  ← 앱이 쓰는 경로\n" "${a:-실패}" "$(( $(date +%s) - s ))"
done

echo
echo "── 4. 실제 접속 ──"
curl -sS -o /dev/null --max-time 20 \
  -w "github.com  dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code} ip=%{remote_ip}\n" \
  https://github.com 2>&1
echo "git ls-remote:"
perl -e "alarm 25; exec @ARGV" git ls-remote https://github.com/git/git HEAD 2>&1 | head -3

echo
echo "── 5. 사내망 도달성 ──"
for ip in 10.0.0.2 10.20.151.155; do
  printf "  %-15s " "$ip"
  ping -c 2 -W 1500 $ip 2>/dev/null | grep -q "bytes from" && echo "응답" || echo "무응답"
done

echo
echo "── 6. 경로 MTU (DF bit) ──"
for s in 1472 1400; do
  r=$(ping -D -s $s -c 3 -W 1200 8.8.8.8 2>/dev/null | grep -oE '[0-9.]+% packet loss' | head -1)
  echo "  payload=$s (IP총 $((s+28))) 손실 ${r:-측정불가}"
done

echo
echo "── 7. OpenVPN 최근 이벤트 ──"
tail -c 6000 "$HOME/Library/Application Support/OpenVPN Connect/log/ovpn_full.log" 2>/dev/null \
  | tr '\r' '\n' | grep -aiE "EVENT|Tunnel Options|error|timeout|PAUSE|RESUME" | tail -12

echo
echo "═══ 끝 ═══"
echo "저장: $OUT"
