# gymboxx-lib entity 맞추기
### 차이 나는 것들
1. 주석·enum→varchar·정밀도·길이·FK 이름·인덱스·테이블 주석	약 2,000건
  런타임 영향 없음, 기계적
2. date·json 타입	24개
  사용처 조사 완료: 그대로 바꿔도 되는 것 12, 응답 형태가 바뀌는 것 9, 깨지는 것 3  처리 방법 결정 필요
3. 엔티티 default 추가·삭제	126개
  save() 반환 객체의 필드가 바뀜. 수용 여부 결정 필요
4. DB 전용 컬럼 매핑	25개
  응답에 필드가 추가됨
5. 생성일이 아닌데 @CreateDateColumn 인 것 8개, 
6. 반대편이 없는 OneToOne 2개
7. 숫자 enum 1개
8. 관계에만 걸린 FK 5개
9. TypeORM 으로 표현 불가	15개
  UpdateDateColumn 8, OneToOne 유니크 5, PK 없는 테이블 1, 중복 FK 1. 예외 목록으로 관리할지 결정
10. 코드와 DB 의 enum 값 불일치	3개	COMING_SOON, MMS·PUSH 는 코드에만, DELETED 는 DB 에만 있음. 버그 후보

### typeORM 0.3
- 이점
  FK 이름을 엔터티에 적을 수 있다.
- 깨지는 것들 정리
  - payment-lambda 적용 테스트 중요

