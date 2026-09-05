-- 목적:
-- DELIVERY_APP/POS 주문에서 menu-food 매칭이 실패해도 customer_order_food가 원본명으로 저장되는지 빠르게 확인한다.
--
-- AI 판정 기준:
-- 1. unnamed_unmatched_food_count = 0 이면 food_id가 없어도 원본명은 보존되고 있다.
-- 2. unmatched_food_count > 0 이고 named_unmatched_food_count = unmatched_food_count 이면
--    "미매칭 메뉴가 customer_order_food로 저장되고 있다"고 판단할 수 있다.
-- 3. no_food_order_count는 별도 확인 경고다. 미매칭 저장 성공/실패 판정을 덮어쓰지 않는다.
--
-- 한계:
-- 원본 요청 menus 배열이 DB에 저장되지 않으므로, 메뉴 여러 개 중 일부 1개만 누락된 경우는 SQL만으로 확정할 수 없다.
-- 1) AI 판정용 요약
with target_orders as (
  select co.id,
    co.store_id,
    co.platform,
    co.device,
    co.order_number,
    co.ordered_at
  from customer_order co
  where co.device in ('DELIVERY_APP', 'POS')
    and co.deleted_yn = 'n'
    and co.canceled_at is null
    and co.ordered_at >= date_sub(now(), interval 14 day)
    and co.ordered_at <= now()
),
food_rows as (
  select t.id as customer_order_id,
    cof.id as customer_order_food_id,
    cof.food_id,
    cof.name,
    cof.price_amount,
    count(cofo.id) as option_count
  from target_orders t
    left join customer_order_food cof on cof.customer_order_id = t.id
    and cof.deleted_yn = 'n'
    left join customer_order_food_option cofo on cofo.customer_order_food_id = cof.id
    and cofo.deleted_yn = 'n'
  group by t.id,
    cof.id,
    cof.food_id,
    cof.name,
    cof.price_amount
)
select count(distinct t.id) as checked_order_count,
  count(
    distinct case
      when f.customer_order_food_id is null then t.id
    end
  ) as no_food_order_count,
  count(f.customer_order_food_id) as saved_food_count,
  count(
    case
      when f.food_id is null
      and f.customer_order_food_id is not null then 1
    end
  ) as unmatched_food_count,
  count(
    case
      when f.food_id is null
      and nullif(trim(f.name), '') is not null then 1
    end
  ) as named_unmatched_food_count,
  count(
    case
      when f.food_id is null
      and nullif(trim(f.name), '') is null
      and f.customer_order_food_id is not null then 1
    end
  ) as unnamed_unmatched_food_count,
  count(
    case
      when f.food_id is null
      and f.option_count > 0 then 1
    end
  ) as unmatched_food_with_option_count,
  max(t.ordered_at) as latest_checked_ordered_at,
  case
    when count(
      case
        when f.food_id is null
        and nullif(trim(f.name), '') is null
        and f.customer_order_food_id is not null then 1
      end
    ) > 0 then 'CHECK_UNNAMED_UNMATCHED_FOOD'
    when count(
      case
        when f.food_id is null
        and f.customer_order_food_id is not null then 1
      end
    ) > 0
    and count(
      case
        when f.food_id is null
        and nullif(trim(f.name), '') is not null then 1
      end
    ) = count(
      case
        when f.food_id is null
        and f.customer_order_food_id is not null then 1
      end
    ) then 'OK_UNMATCHED_FOOD_SAVED_WITH_NAME'
    else 'NO_UNMATCHED_FOOD_IN_PERIOD'
  end as ai_judgement,
  case
    when count(
      distinct case
        when f.customer_order_food_id is null then t.id
      end
    ) > 0 then 'WARN_NO_FOOD_ORDER_EXISTS'
    else 'OK_NO_FOOD_ORDER_NOT_FOUND'
  end as integrity_warning
from target_orders t
  left join food_rows f on f.customer_order_id = t.id;
-- 2) 미매칭 주문 상세: food_id는 없지만 customer_order_food row와 원본명이 저장됐는지 확인
with option_counts as (
  select cofo.customer_order_food_id,
    count(*) as option_count
  from customer_order_food_option cofo
  where cofo.deleted_yn = 'n'
  group by cofo.customer_order_food_id
)
select co.id as customer_order_id,
  co.store_id,
  co.platform,
  co.device,
  co.order_number,
  co.ordered_at,
  count(cof.id) as saved_food_count,
  count(
    case
      when cof.food_id is null then 1
    end
  ) as unmatched_food_count,
  sum(cof.price_amount) as saved_food_price_sum,
  group_concat(
    case
      when cof.food_id is null then concat(
        cof.id,
        ':',
        coalesce(nullif(trim(cof.name), ''), '[NO_NAME]'),
        '(price=',
        cof.price_amount,
        ', options=',
        coalesce(oc.option_count, 0),
        ')'
      )
    end
    order by cof.id separator ' | '
  ) as unmatched_foods
from customer_order co
  join customer_order_food cof on cof.customer_order_id = co.id
  and cof.deleted_yn = 'n'
  left join option_counts oc on oc.customer_order_food_id = cof.id
where co.device in ('DELIVERY_APP', 'POS')
  and co.deleted_yn = 'n'
  and co.canceled_at is null
  and co.ordered_at >= date_sub(now(), interval 14 day)
  and co.ordered_at <= now()
group by co.id,
  co.store_id,
  co.platform,
  co.device,
  co.order_number,
  co.ordered_at
having unmatched_food_count > 0
order by co.ordered_at desc,
  co.id desc
limit 100;
-- 3) 미매칭 이름별 해결 후보: 같은 원본명이 반복되면 menu-food 매핑 보완 대상으로 본다.
select cof.name as original_food_name,
  case
    when cof.name like '%리뷰%' then 'review_event'
    when cof.name like '%쿠폰%' then 'coupon'
    when cof.name in ('매장식사', '포장', '계좌이체') then 'service_marker'
    when cof.name like '%직원)%' then 'staff_item'
    when cof.name like '%할인%' then 'discount_marker'
    when cof.name regexp '^[0-9]+$' then 'manual_amount'
    when cof.name like '%소스%'
    or cof.name in ('순한맛', '중간매운맛', '매운맛') then 'option_like'
    when cof.name like '%추가%' then 'add_on'
    else 'menu_mapping_candidate'
  end as candidate_type,
  case
    when cof.name like '%리뷰%' then 8
    when cof.name like '%쿠폰%' then 8
    when cof.name in ('매장식사', '포장', '계좌이체') then 9
    when cof.name like '%직원)%' then 7
    when cof.name like '%할인%' then 7
    when cof.name regexp '^[0-9]+$' then 7
    when cof.name like '%소스%'
    or cof.name in ('순한맛', '중간매운맛', '매운맛') then 4
    when cof.name like '%추가%' then 3
    else 1
  end as candidate_priority,
  count(*) as unmatched_food_count,
  count(distinct co.id) as order_count,
  count(distinct co.store_id) as store_count,
  min(co.ordered_at) as first_ordered_at,
  max(co.ordered_at) as last_ordered_at,
  group_concat(
    distinct co.platform
    order by co.platform separator ', '
  ) as platforms,
  group_concat(
    distinct co.device
    order by co.device separator ', '
  ) as devices,
  left(
    group_concat(
      co.order_number
      order by co.ordered_at desc separator ', '
    ),
    300
  ) as sample_order_numbers
from customer_order_food cof
  join customer_order co on co.id = cof.customer_order_id
where cof.food_id is null
  and nullif(trim(cof.name), '') is not null
  and cof.deleted_yn = 'n'
  and co.device in ('DELIVERY_APP', 'POS')
  and co.deleted_yn = 'n'
  and co.canceled_at is null
  and co.ordered_at >= date_sub(now(), interval 14 day)
  and co.ordered_at <= now()
group by cof.name,
  candidate_type,
  candidate_priority
order by candidate_priority asc,
  unmatched_food_count desc,
  last_ordered_at desc
limit 100;
-- 4) 우선 확인해야 하는 이상 징후
-- no_food_order: 주문은 있으나 customer_order_food가 하나도 없다.
-- unnamed_unmatched_food: food_id도 없고 원본명도 없어 KDS/운영 화면에서 식별이 어렵다.
select 'no_food_order' as issue_type,
  co.id as customer_order_id,
  co.store_id,
  co.platform,
  co.device,
  co.order_number,
  co.ordered_at,
  null as customer_order_food_id,
  null as food_name,
  null as price_amount
from customer_order co
  left join customer_order_food cof on cof.customer_order_id = co.id
  and cof.deleted_yn = 'n'
where co.device in ('DELIVERY_APP', 'POS')
  and co.deleted_yn = 'n'
  and co.canceled_at is null
  and co.ordered_at >= date_sub(now(), interval 14 day)
  and co.ordered_at <= now()
  and cof.id is null
union all
select 'unnamed_unmatched_food' as issue_type,
  co.id as customer_order_id,
  co.store_id,
  co.platform,
  co.device,
  co.order_number,
  co.ordered_at,
  cof.id as customer_order_food_id,
  cof.name as food_name,
  cof.price_amount
from customer_order co
  join customer_order_food cof on cof.customer_order_id = co.id
  and cof.deleted_yn = 'n'
where co.device in ('DELIVERY_APP', 'POS')
  and co.deleted_yn = 'n'
  and co.canceled_at is null
  and co.ordered_at >= date_sub(now(), interval 14 day)
  and co.ordered_at <= now()
  and cof.food_id is null
  and nullif(trim(cof.name), '') is null
order by ordered_at desc,
  customer_order_id desc
limit 100;