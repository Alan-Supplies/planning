/deploy: 코드베이스를 분석해서 프레임워크, DB, 의존성을 파악하고 적절한 AWS 서비스를 추천합니다. 비용을 먼저 추정한 뒤, 동의하면 IaC 생성과 배포 단계로 진행합니다.
/aws-architecture-diagram: AWS 아키텍처를 draw.io 다이어그램으로 생성합니다. 기존 IaC/CDK/Terraform을 분석하거나, 새 아키텍처를 설명하면 .drawio 파일을 만들고 검증합니다.
/elastic-beanstalk: Elastic Beanstalk 배포 전용 스킬입니다. “서버 관리하기 싫다”, “Heroku처럼 운영하고 싶다”, “EB로 배포” 같은 요청에 맞춰 웹 서버/워커 환경을 구성합니다.