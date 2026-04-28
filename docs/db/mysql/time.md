### datetime
- 2038년 이후 가능
- timezone 변환 없음
- DEFAULT CURRENT_TIMESTAMP, ON UPDATE CURRENT_TIMESTAMP -> 커넥션 따라 다름
- 
### timestamp
- utc 강제
- 읽을 때는 @@session.time_zone 기준
- DEFAULT CURRENT_TIMESTAMP, ON UPDATE CURRENT_TIMESTAMP -> UTC 입력

### 회사기준
- utc 강제
