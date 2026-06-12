[주제: typeORM]
```
const platformOptions = await dataSource.query(`
      SELECT
        po.name AS platformName,
        po.option_id AS optionId,
        o.id AS id,
        od.name AS optionName,
        o.option_type AS type,
        o.meat_type AS meatType,
        o.designated_position AS designatedPosition,
        o.status AS status
      FROM platform_option po
      LEFT JOIN \`option\` o ON o.id = po.option_id
      LEFT JOIN option_detail od ON od.option_id = o.id AND od.country_code = 'KOR'
    `) as PlatformOptionRow[]
```
위 코드를 typeORM repository 불러서 사용하려고 했는데
relation이 nested로 나오는 구조보다
od.name AS optionName,
처럼 바로 불러오는 것도 상당히 편리함
하지만 country_code='KOR' 이 여러행 일경우는 잘못된 상황인데 서비스에 영향 미칠 수 있다.
더 좋은 판단을 내리기 위한 의견필요