- 보안 중요성
  공격 준비 기간 2.3year -> 1day
# AI 시대의 보안 트렌드
Datadog이 제안하는 보안전략
- openai의 허깅페이스 해킹 사건
기간 4.5일
액션: 17,600건
시험문제를 풀라고 했더니 왜 답안지를 훔쳤을까?

agent(sandbox) -> api gateway(패키지 설치용)
--- 인터넷
포적 탐색
--- 허깅 페이스
악성 데이터셋

# 보안 check point
프롬프트 인젝션 차단
코드 취약점 통제가 가능?
LLM에서 발생하는 공격 통제
쉐도우 AI(게이트웨이를 거치지 않는)

- 코드 취약점(SAST - 정적 어플리케이션 보안)

- 비인가 모델 가시성 확보(AI Guard - Discover)
- 서비스 운영환경
  실행 중인 취약 라이블러리
  SQL인젝션
  멀웨어 및 명령어 추적
- 런타임 컨텍스트로 노이즈 평균 90% 감소
  Crown Jewel 정의
- 공격 체인 자동 재구성 및 프레시스                                                              -
- AI Speed 보안
  새로운 방법이 계속 나오는데 빠르게 대응해야 함
- 세션 실습

### HALO (메가존)
SIEM+CSM+ASM

Cloud SIEM
SQL 기반 탐지

### 프롬프트 인젝션
이미지 다운 스케일링 결과 인젝션 있음
간접프롬프트
Rag poisoning
- LLM 보안
  Code, Cloud, runtime, agent
보안 레이어
1. 빌드
2. 런타임
3. 거버넌스

# 원인 파악까지 단 5분
Datadog MCP + Claude
- 코드보안
  오픈소스 취약점, IaC 보안
- 칼라우드 보안
-  애플리케이션 보안
IAST Threat Management
- 워크로드 & SIEM

### security inbox
보안 문제 모아서 보기
### automation

# MetanetX
보안관제 센터
- 사례
로그인 실패 분포
# 모요
1. 수집
2. 탐지
3. 대응
### github PAT 유출 **사건**
1. 컨텍스트 1개
2. +Okta 사람의 인증 기록
3. + Slack 조직만 아는 맥락
4. ?
### Bits AI Agent builder
### 구성
1. infisical 운영 시크릿
2. 구글 워크스페이스
3. AWS SG, IAM Role
### 유틸
- 슬랙 보안 사항 reminder
- WAF 로그 모니터링

# 환화비전 SIEM, CSM
DevSecOps, DevOpsSec은 다르다.
SOC2 감사
- hub spoke architecture
  멀티 허브?
  허브끼리는 Transit Gateway

DevSecOps 구성 어려움
1. 인력
2. 비용 탄력성
  Datadog
  계정 구조 -> CSM
  로그 선별 -> SIEM 비용
  포인트에만 적용
  AWS계정 설계
3. 경로 단일성
  테라폼 단일 경로, EBS 볼륨 암호화, IP제한, 방화벽, 리뷰필수
  잡아야할 것 자체가 줄어듬
그래서 DevSecOps
claude로 datadog mcp 안쓸 이유가 없다.
분석은 무조건 AI
데이터독 주식사라
****