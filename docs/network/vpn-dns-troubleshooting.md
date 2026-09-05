# 재택 VPN — DNS / MTU 트러블슈팅

> 최초 작성 2026-08-30 · 최종 갱신 2026-09-04

## 요약

집에서 VPN 을 켜면 `git pull` 등 **일반 인터넷 접근이 실패**한다는 증상에서 출발했다.
VPN 서버가 **모든 DNS 질의를 사내 DNS 한 곳으로 강제**(`block-outside-dns`)하는 구성이 원인으로 **지목**되었으나,
진단 중 증상을 **재현하지 못했다**. 원인은 아직 **미확정**이다.

로컬 우회책(`/etc/resolver/` 로 split DNS 흉내)을 시도했다가 **DB 접속과 VPN 재연결을 두 차례 깨뜨렸고**,
전부 롤백했다. 근본 해결은 **서버 측 split DNS 전환**이다. 아래 [남은 일](#남은-일) 참고.

---

## VPN 구성 (실측)

| 항목 | 값 |
| --- | --- |
| 클라이언트 | OpenVPN Connect (macOS) |
| 서버 | `vpn.supp.fitness` → `54.116.132.139` : **1194/UDP** |
| 터널 방식 | **split tunnel** — 기본 경로는 로컬 회선, 사내 대역만 터널 |
| 터널 주소 | `192.168.255.10` → `192.168.255.9` (/30, net30 토폴로지) |
| 사내 라우트 | `10.0/16`~`10.20/16`, `172.16/12`, `172.31/16`, 일부 `/32` |
| 암호 | `BF-CBC` + `SHA1` ⚠️ |
| MTU | `link-mtu 1541`, `tun-mtu 1500`, `mtu=(default)` ⚠️ |

서버가 클라이언트에 push 하는 옵션 (연결 로그 기준):

```
0 [block-outside-dns]
1 [dhcp-option] [DNS] [10.0.0.2]

MacDNSAction: FLAGS=ESF RD=1 SO=5000 DNS=10.0.0.2 RSD= DOM=
```

`DOM=` 이 **비어 있다** = 도메인 한정이 없다 = **모든 도메인**이 사내 DNS(`10.0.0.2`)를 거친다.
`block-outside-dns` 는 macOS 의 다른 DNS 설정을 덮어써 **폴백을 없앤다.**

---

## 확인된 사실

### 1. DNS 가 사내 한 곳에 묶여 있다 — 사실

위 로그가 근거. split DNS 가 아니라 전체 리다이렉트다.
사내에서는 `10.0.0.2` 가 같은 LAN 이라 무해하지만, 재택에서는 **일반 사이트 이름 해석까지 터널을 탄다.**

### 2. MTU 가 초과 설정되어 있다 — 사실

```
link-mtu 1541 + UDP 8 + IP 20 = 1569 bytes  >  이더넷 MTU 1500
```

풀사이즈 패킷마다 **IP fragment 가 강제로 발생**한다.
다만 실측 결과 집 회선에서 **fragment 는 통과했다** (터널 경유 1472 바이트 정상 왕복).
즉 지금 당장 끊기지는 않으나, 패킷 수가 2배가 되고 조각 하나만 잃어도 전체 재전송이라 **느리고 취약하다.**
회선이 바뀌면(카페 Wi-Fi, LTE 테더링) 그때 드롭될 수 있다.

### 3. 암호 스위트가 구식 — 사실 (이번 건과 무관)

`BF-CBC` = Blowfish 64비트 블록 → **SWEET32 (CVE-2016-2183)** 대상. `SHA1` 도 마찬가지.
`AES-256-GCM` + `SHA256` 으로 교체 권장.

### 4. 원래 증상의 원인 — **미확정**

진단 내내 GitHub 은 정상이었다 (`HTTP 200`, 0.077s).
관측된 것은 `dig github.com AAAA @10.0.0.2` 와 `dig vpn.supp.fitness` 의 **산발적 타임아웃** 뿐이고,
재측정하면 정상으로 돌아왔다. 1·2번은 사실이지만 **그것이 증상의 원인이라는 입증은 없다.**

---

## 사내 프라이빗 도메인 (중요)

사내 DNS(`10.0.0.2`)에만 존재하고 **공용 DNS 로는 해석되지 않는** 존:

| 도메인 | 비고 |
| --- | --- |
| `supp.kr` | **사내 전용.** 예: `db.gymboxx.dev.supp.kr` → CNAME → `dev-gymboxx-rds.*.rds.amazonaws.com` → `10.20.151.155` |
| `supp.fitness` | VPN 서버(`vpn.supp.fitness`)가 여기 속함 — 아래 함정 참고 |

반면 **공용 DNS 로도 동일하게 해석되는** 것들 (사내 DNS 불필요):

- `*.rds.amazonaws.com` — AWS 가 퍼블릭 DNS 에 프라이빗 IP 를 공개한다
- `*.eks.amazonaws.com`
- `suppliesfitness.com`

> 이 목록은 **관측된 범위**일 뿐 전수 조사가 아니다. 다른 사내 존이 더 있을 수 있다.

---

## 시도했다가 롤백한 것 — 같은 실수 반복 금지

`/etc/resolver/<tld>` 로 "공개 TLD 는 공용 DNS, 사내 도메인은 사내 DNS" 를 로컬에서 흉내 냈다.
**이틀 사이 두 번 사고가 났고 전부 롤백했다.**

| # | 만든 규칙 | 터진 것 | 원인 |
| --- | --- | --- | --- |
| 1 | `/etc/resolver/supp.fitness` → `10.0.0.2` | **VPN 연결 자체가 timeout** | VPN 서버 주소가 `vpn.supp.fitness`. 붙으려면 이름을 풀어야 하는데 그 DNS 가 **터널 안에** 있다 → 순환 의존. `dig` 는 `/etc/resolver/` 를 안 보므로 정상으로 보이고, 앱이 쓰는 `dscacheutil` 만 60초 타임아웃 → **진단이 어긋난다** |
| 2 | `/etc/resolver/kr` → `1.1.1.1` | **DB 접속 불가** (`ERROR 2005 Unknown MySQL server host`) | `supp.kr` 이 사내 전용 존인 걸 몰랐다. `.kr` 을 공개 TLD 로 단정한 게 오류 |

**교훈 — `/etc/resolver/` 를 TLD 단위로 가르지 말 것.**
사내 프라이빗 존이 어느 TLD 에 얹혀 있는지 **전부** 알기 전에는 계속 터진다.
그리고 이 방식은 **본인 맥에만** 적용되므로, "나만 안 되는" 장애를 스스로 만드는 셈이다.

롤백: `bash ~/Downloads/vpn-dns-rollback.sh` (= `sudo rm -rf /etc/resolver` + DNS 캐시 flush)

---

## 남은 일

### 1순위 — 원인 입증

서버를 건드리기 전에 증상이 실재하는지부터 확정한다.

- 재택 팀원에게 확인: **"집에서 VPN 켜고 `git pull` 이 멈추거나 실패한 적 있나?"**
  - 있다 → 서버 설정 문제로 확정. 2순위 진행
  - 없다 → 이 문서의 진단이 틀렸다. 처음부터 다시
- 증상 재발 시 **그 자리에서** 아래 [진단 명령](#진단-명령) 을 돌려 기록을 남긴다

### 2순위 — 서버 측 수정 (근본 해결)

VPN 서버(`54.116.132.139`)의 `/etc/openvpn/server.conf`. **클라이언트 `.ovpn` 이 아니다** — `push` 는 서버 전용 지시어다.

```conf
push "dhcp-option DNS 10.0.0.2"
push "dhcp-option DOMAIN supp.kr"        # 추가 — 사내 도메인만 사내 DNS 로
push "dhcp-option DOMAIN supp.fitness"   # 추가
# push "block-outside-dns"               # 제거 — 폴백 DNS 를 막지 않는다

tun-mtu 1400                             # fragment 제거
mssfix 1360

cipher AES-256-GCM                       # BF-CBC 교체
auth SHA256
```

절차:

```sh
sudo grep -rn "block-outside-dns" /etc/openvpn/
sudo cp /etc/openvpn/server.conf /etc/openvpn/server.conf.bak.$(date +%F)
# 편집 후
sudo systemctl restart openvpn@server
```

⚠️ **재시작하면 접속 중인 팀원 전원의 VPN 이 끊긴다.** 업무 시간을 피하고 사전 공지할 것.
롤백은 백업 복원 후 재시작.

### 3순위 — 클라이언트 MTU (선택)

`~/Downloads/alan-mtu-fix.ovpn` 에 `tun-mtu 1400` / `mssfix 1360` / `persist-tun` / `persist-key` 를 넣어둔 프로파일이 있다.
OpenVPN Connect 에서 임포트해 사용. 서버가 2순위로 고쳐지면 불필요하다.

---

## 진단 명령

### 증상 발생 시 — 스냅샷 스크립트

증상이 난 **그 자리에서** 아래를 실행한다. 결과가 `~/Downloads/vpn-diag-<시각>.txt` 로 저장된다.

```sh
bash planning/docs/network/vpn-diag.sh
```

VPN 상태 · DNS 설정 · 이름 해석 4경로 비교 · 실제 접속 타이밍 · 사내망 도달성 · 경로 MTU · OpenVPN 최근 이벤트를 한 번에 담는다.
평온할 때 한 번 떠 두고 **증상 시점과 비교**하면 차이가 바로 드러난다.

### 개별 명령

```sh
# VPN 연결 여부
ifconfig | grep -q "192.168.255" && echo 연결됨 || echo 미연결
netstat -rn -f inet | grep -E "^(default|10[./]|172\.(16|31)|192\.168\.255)"

# 서버가 push 한 옵션 / 연결 이벤트
grep -a "Tunnel Options\|CONNECTED\|EVENT" \
  ~/Library/Application\ Support/OpenVPN\ Connect/log/ovpn_full.log | tail -20

# 이름 해석 — 두 경로를 반드시 같이 본다
dig <호스트> +short                      # /etc/resolv.conf 만 참조. /etc/resolver/ 를 무시한다
dscacheutil -q host -a name <호스트>     # 앱이 실제로 쓰는 경로. 이쪽이 진실

# 사내 DNS 전용 존인지 판별
dig <호스트> +short @10.0.0.2            # 사내
dig <호스트> +short @1.1.1.1             # 공용 — 여기서 안 나오면 사내 전용

# 경로 MTU (DF bit)
ping -D -s 1472 -c 3 8.8.8.8             # 1472+28=1500 통과하면 회선 MTU 정상
```

> `dig` 와 `dscacheutil` 이 **다른 답을 내면 `/etc/resolver/` 를 의심**한다. 사고 #1 을 놓친 이유가 이것이다.

## DB 접속

접속 정보는 `~/.claude/gymboxx-db.md`. 이름 해석이 의심되면 **IP 직접 접속**으로 네트워크와 DNS 를 분리해 판별한다.

```sh
mysql gymboxx -h 10.20.151.155 -u readonly_ssl -p --ssl-mode=REQUIRED -e "SELECT VERSION()"
```

IP 로 붙는데 도메인으로 안 붙으면 → **순수 DNS 문제.** VPN·방화벽·계정은 정상.
