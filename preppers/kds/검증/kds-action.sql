select ko.id, ko.store_id, s.name
	, ko.order_id, ko.service_type
	, co.service_type co_service_type
	from kds_order ko
		left join customer_order co on co.id = ko.order_id
		left join store s on s.id = ko.store_id
	where ko.id = 23174
	order by ko.id desc
	limit 5;