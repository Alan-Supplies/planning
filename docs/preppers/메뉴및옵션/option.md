1. 신규 테이블
```ts
  interface platform_option {
    id: number
    name string: string // unique
    option_id: string
  }
```

2. 기존 테이블 복사
```sql
insert ignore into platform_option (name)
  select name from options;
```

3. option mapping
AI 분석?
