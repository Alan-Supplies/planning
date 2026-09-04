### GYMBOXX MYSQL
- 개발 읽기 전용 계정
  host: db.gymboxx.dev.supp.kr
  user: readonly_ssl
  password: probe0929
  database: gymboxx
- 운영 읽기 전용 계정
  host: db-ro.gymboxx.prod.supp.kr
  user: readonlyuser
  password: supplies12
  database: gymboxx

#### 접속 주의 (2026-09-04 검증)

- **운영은 `db-ro` 만 쓴다.** `gymboxx-prod.cxubxpnokvfs.ap-northeast-2.rds.amazonaws.com` 도 같은 계정으로
  붙지만 그쪽은 라이터 인스턴스(`@@read_only = 0`)다. `db-ro` 는 리드 레플리카(`@@read_only = 1`).
  조회 부하를 라이터로 보내지 않도록 `db-ro` 를 정본으로 쓴다.
- **개발은 SSL 필수 + MySQL 8 클라이언트가 필요하다.** PATH 의 `mysql` 은 MariaDB 클라이언트여서
  `--ssl-mode` 옵션이 없다. 아래처럼 8.2 클라이언트를 명시한다.

  ```sh
  MYSQL_PWD=probe0929 /opt/homebrew/opt/mysql-client@8.2/bin/mysql \
    -h db.gymboxx.dev.supp.kr -u readonly_ssl -D gymboxx \
    --ssl-mode=REQUIRED --connect-timeout=10 -e 'select 1;'
  ```

  `--ssl-mode` 없이 붙으면 `TLS/SSL error: self-signed certificate in certificate chain` 이 난다.
- 운영은 SSL 없이 붙는다 — `--skip-ssl` 사용 가능.
- 개발과 운영은 데이터가 다르다 — `exercise` 종목 수 개발 275 · 운영 273. 실측 근거를 문서에 쓸 때는
  어느 쪽 DB인지 반드시 명기한다.

