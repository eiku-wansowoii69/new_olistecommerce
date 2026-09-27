CREATE OR REPLACE VIEW ads.vw_seller_delivery_performance AS
SELECT
    fo.order_id,
    foi.order_item_id,
    fo.order_purchase_timestamp,
    TO_CHAR(fo.order_purchase_timestamp, 'YYYY-MM') AS year_month,
    fo.order_status,
    foi.product_id,
    dp.product_category_name,
    foi.seller_id,
    ds.seller_state,
    ds.seller_city,
    fo.delivery_days,
    fo.order_delivered_customer_date,
    fo.order_estimated_delivery_date,
    CASE
        WHEN fo.order_delivered_customer_date IS NULL THEN 'unknown'
        WHEN fo.order_delivered_customer_date > fo.order_estimated_delivery_date
        THEN 'late'
        ELSE 'on_time'
    END AS late_flag,
    foi.price,
    foi.freight_value,
    fr.review_score
FROM dwd.fact_orders fo
INNER JOIN dwd.fact_order_items foi ON foi.order_id = fo.order_id
LEFT JOIN dwd.dim_sellers ds ON ds.seller_id = foi.seller_id
LEFT JOIN dwd.dim_products dp ON dp.product_id = foi.product_id
LEFT JOIN (
    SELECT order_id, ROUND(AVG(review_score))::integer AS review_score
    FROM dwd.fact_order_reviews
    GROUP BY order_id
) fr ON fr.order_id = fo.order_id
WHERE fo.load_batch_id = (
    SELECT MAX(batch_id) FROM raw.etl_log
    WHERE layer = 'dwd' AND status = 'success'
);