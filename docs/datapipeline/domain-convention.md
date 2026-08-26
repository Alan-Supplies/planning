### S3 / Glue / Athena (Bronze)
- S3 Bucket
규칙: <company>-<layer>-<env>
예: supplies-bronze-dev
- S3 Key 경로
규칙: <product>/<database>/<table>/<load_type>/<yyyy-mm-dd(-hh)>
예: gymboxx/gymboxx/user/cdc/2026-08-15
- Glue Database
규칙: <env>_<product>
예: dev_gymboxx
- Glue Table
규착: <table>_<load_type>
예: membership_cdc
### DMS
- 네트워크 자원
규칙: <env>-dms-<purpose>
예: `dev-dms`, `dev-dms-sg`, `dev-dms-app-subnet-group`, `dev-dms-s3-target-role`
- Endpoint — source/target
   - source
      규칙: <env>-<product>-<engine>-source
      예: dev-gymboxx-mysql-source
   - target
     규칙: <env>-<product>-bronze-<load_type>
     예: dev-gymboxx-bronze-full
- Task
   규칙: <env>-<product>-<load_type>
   예: dev-gymboxx-full
- secrets manager
   규칙: <product>/<env>/<purpose>
