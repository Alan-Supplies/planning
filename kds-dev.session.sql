-- 음식이름
select co.id, co.store_id
	, cof.name, cof.food_id
	, cof.name
	, fd.name
	, co.platform, co.device
	, co.order_number
	, co.ordered_at
	from customer_order_food cof 
		left join customer_order co on co.id = cof.customer_order_id
		left join food_detail fd on fd.food_id = cof.food_id and country_code = 'KOR'
	where cof.food_id is null
	order by cof.id desc
	limit 20;