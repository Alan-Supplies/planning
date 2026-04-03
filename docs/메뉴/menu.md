CREATE TABLE `menu` (
  `id` int NOT NULL AUTO_INCREMENT,
  `food_id` int DEFAULT NULL,
  `name` varchar(100) NOT NULL,
  `unique_name` varchar(100) DEFAULT NULL,
  `type` varchar(50) NOT NULL,
  `meat_type` varchar(50) DEFAULT NULL,
  `designated_position` varchar(10) DEFAULT NULL,
  `hall_price` int DEFAULT NULL,
  `delivery_price` int DEFAULT NULL,
  `is_pos_key` tinyint(1) NOT NULL DEFAULT '0',
  `status` varchar(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '메뉴 상태',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=480 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
