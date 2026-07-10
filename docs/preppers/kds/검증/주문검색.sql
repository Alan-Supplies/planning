-- by id
select co.id, co.store_id, co.order_number
  , ko.id, ko.display_status
  , ko.ordered_at, ko.updated_at, ko.position_completed_at
  FROM customer_order co
  left join kds_order ko on ko.order_id = co.id
  where co.id = 1134085;