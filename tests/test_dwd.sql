--测试olist_orders_dataset
SELECT *
FROM raw.olist_orders_dataset

SELECT order_id FROM raw.olist_orders_dataset
WHERE order_id IS NULL OR order_id=''

SELECT customer_id FROM raw.olist_orders_dataset
WHERE customer_id IS NULL OR customer_id=''

SELECT DISTINCT order_status FROM raw.olist_orders_dataset

SELECT order_status 
FROM raw.olist_orders_dataset
WHERE order_status!=TRIM(order_status)

SELECT order_purchase_timestamp 
FROM raw.olist_orders_dataset
WHERE order_purchase_timestamp!=TRIM(order_purchase_timestamp)
OR order_purchase_timestamp IS NULL OR order_purchase_timestamp=''

SELECT order_approved_at 
FROM raw.olist_orders_dataset
WHERE order_approved_at!=TRIM(order_approved_at)
OR order_approved_at IS NULL OR order_approved_at=''

SELECT order_delivered_carrier_date 
FROM raw.olist_orders_dataset
WHERE order_delivered_carrier_date!=TRIM(order_delivered_carrier_date)
OR order_delivered_carrier_date IS NULL OR order_delivered_carrier_date=''

--测试dwd.olist_order_items_dataset
SELECT *
FROM raw.olist_order_items_dataset

--既然有固定格式感觉就不太需要测试了
--dwd.olist_products_dataset
SELECT *
FROM raw.olist_products_dataset

--dwd.olist_sellers_dataset
SELECT *
FROM raw.olist_sellers_dataset

 

