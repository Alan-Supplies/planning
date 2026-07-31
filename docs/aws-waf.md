# AWS WAF 간단 정리

## 개요

AWS WAF(Web Application Firewall)는 웹 애플리케이션으로 들어오는
HTTP/HTTPS 요청을 검사하고, 조건에 따라 허용하거나 차단하는 AWS 서비스다.

주로 다음 리소스 앞에 연결해 사용한다.

- Amazon CloudFront
- Application Load Balancer(ALB)
- Amazon API Gateway
- AWS AppSync 등 AWS WAF가 지원하는 애플리케이션 리소스

AWS WAF는 네트워크 포트 접근을 제어하는 Security Group이나 NACL과 다르다.
요청 경로, 쿼리 문자열, 헤더, 쿠키, 요청 본문, 접속 IP처럼 웹 요청의 내용을
기준으로 제어하는 **애플리케이션 계층(L7) 방화벽**이다.

## 주요 구성 요소

### Web ACL

보호할 AWS 리소스에 연결하는 정책 묶음이다. 여러 규칙을 우선순위에 따라
평가하며, 어떤 규칙에도 일치하지 않을 때 적용할 기본 동작도 설정한다.

### Rule

요청을 검사할 조건과 일치했을 때의 동작을 정의한다.

대표적인 조건:

- 특정 IP 또는 IP 대역
- 국가 또는 지역
- URI 경로와 쿼리 문자열
- HTTP 헤더와 쿠키
- SQL Injection, Cross-Site Scripting(XSS) 패턴
- 일정 시간 동안의 요청 횟수

대표적인 동작:

- `Allow`: 요청 허용
- `Block`: 요청 차단
- `Count`: 차단하지 않고 탐지 건수만 기록
- `CAPTCHA`: CAPTCHA 검증 요구
- `Challenge`: 브라우저 챌린지 수행

### Managed Rule Group

AWS 또는 보안 공급자가 관리하는 규칙 모음이다. 일반적인 웹 공격, 악성 IP,
봇과 같은 위협에 빠르게 대응할 수 있다.

운영에 바로 `Block`으로 적용하면 정상 요청이 차단될 수 있으므로, 처음에는
`Count`로 적용하고 탐지 결과를 확인한 뒤 차단으로 전환하는 것이 안전하다.

## Rate limit 설정

AWS WAF의 **rate-based rule**을 사용하면 동일한 기준으로 집계된 요청이 일정
횟수를 초과할 때 추가 요청을 차단하거나 CAPTCHA 등의 동작을 적용할 수 있다.

예를 들어 로그인 API에 다음 정책을 적용할 수 있다.

| 항목 | 설정 예시 |
|---|---|
| 대상 요청 | `POST /api/login` |
| 집계 기준 | Source IP |
| 평가 구간 | 5분 |
| 제한 | IP당 300회 |
| 초과 시 동작 | `Block` |

이 설정은 각 IP에서 최근 5분 동안 로그인 API를 호출한 횟수를 집계하고,
설정한 기준을 넘은 IP의 추가 요청을 차단한다.

AWS WAF에서 선택할 수 있는 평가 구간은 1분, 2분, 5분, 10분이며 기본값은
5분이다. 설정 가능한 최소 요청 횟수는 10회다.

### 설정 순서

1. AWS WAF에서 Web ACL을 생성하고 보호 대상 리소스에 연결한다.
2. `Rate-based rule`을 추가한다.
3. 평가 구간과 요청 제한 값을 입력한다.
4. 집계 기준을 Source IP 또는 필요한 사용자 정의 키로 선택한다.
5. 특정 API에만 적용하려면 scope-down statement로 URI와 HTTP Method 조건을
   추가한다.
6. 처음에는 `Count`로 운영해 정상 사용자의 요청량을 확인한다.
7. 적절한 임계값을 결정한 후 `Block`, `CAPTCHA` 또는 `Challenge`로 전환한다.

### 설정 시 주의사항

- AWS WAF의 rate limit은 요청량을 근사 계산하므로 정확한 API quota나
  과금용 제한 기능으로 사용하면 안 된다.
- 제한 초과를 감지하거나 제한을 해제하는 데 짧은 지연이 발생할 수 있다.
- NAT, 프록시 또는 사내망을 사용하는 다수 사용자가 하나의 IP로 보일 수
  있으므로 IP 기준 제한이 정상 사용자를 함께 차단할 수 있다.
- 프록시의 `X-Forwarded-For` 헤더를 기준으로 집계할 경우, 신뢰할 수 있는
  프록시가 헤더를 올바르게 설정하는지 확인해야 한다.
- 로그인, 인증번호 요청, 검색, 주문 생성처럼 API 특성이 다른 경로에는
  각각 다른 임계값을 적용하는 것이 좋다.
- 규칙 설정을 변경하면 기존 rate count가 초기화되어 제한 적용이 잠시
  중단될 수 있다.

## 권장 기본 구성

초기 구성은 다음 순서가 무난하다.

1. AWS Managed Rules의 일반 보호 규칙을 `Count`로 적용한다.
2. 오탐 여부를 확인한 뒤 필요한 규칙을 `Block`으로 전환한다.
3. 로그인과 같이 공격 또는 남용 가능성이 높은 API에 rate-based rule을
   추가한다.
4. CloudWatch Metrics와 AWS WAF 로그에서 차단량, 주요 IP, 요청 경로,
   오탐 여부를 관찰한다.
5. 반복적으로 차단되는 명확한 악성 IP는 IP set으로 별도 관리한다.

Rate limit 임계값은 임의로 정하기보다 정상 트래픽의 최대 요청량을 먼저
측정하고, 순간적인 트래픽 증가를 수용할 수 있도록 여유를 둬야 한다.
애플리케이션 내부의 사용자별 quota가 필요한 경우에는 API Gateway usage
plan이나 애플리케이션·Redis 기반 제한을 함께 사용한다.

## 참고 자료

- [AWS WAF 개요](https://docs.aws.amazon.com/waf/latest/developerguide/what-is-aws-waf.html)
- [AWS WAF 규칙](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rules.html)
- [Rate-based rule 설정](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)
- [Rate-based rule 주의사항](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)
- [AWS WAF 할당량](https://docs.aws.amazon.com/waf/latest/developerguide/limits.html)
