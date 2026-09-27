CREATE OR REPLACE VIEW ads.vw_exec_sales_overview AS
SELECT
    fo.order_id,
    foi.order_item_id,
    fo.order_purchase_timestamp,
    TO_CHAR(fo.order_purchase_timestamp, 'YYYY-MM') AS year_month,
    fo.order_status,
    dc.customer_id,
    dc.customer_unique_id,
    dc.customer_state,
    dc.customer_city,
    foi.product_id,
    dp.product_category_name,
    foi.price,
    foi.freight_value,
    fr.review_score,
    CASE WHEN dc.customer_unique_id IN (
        SELECT customer_unique_id
        FROM dwd.dim_customers dc2
        JOIN dwd.fact_orders fo2 ON fo2.customer_id = dc2.customer_id
        GROUP BY customer_unique_id
        HAVING COUNT(DISTINCT fo2.order_id) >= 2
    ) THEN 1 ELSE 0 END AS repeat_flag
FROM dwd.fact_orders fo
LEFT JOIN dwd.fact_order_items foi ON foi.order_id = fo.order_id
LEFT JOIN dwd.dim_customers dc ON dc.customer_id = fo.customer_id
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