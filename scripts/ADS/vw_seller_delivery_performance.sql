/*
脚本名称：vw_seller_delivery_performance.sql
功能：创建应用数据层（ads schema）的卖家配送绩效视图（vw_seller_delivery_performance），
      关联 DWD 层的订单主表、订单明细、卖家、商品及评价汇总数据，整合成宽表，
      用于支撑卖家维度的配送时效、延迟情况及评分分析看板。
说明：脚本使用 CREATE OR REPLACE VIEW 创建视图，支持可重复运行；
      以订单明细（fact_order_items）为基准，通过 INNER JOIN 关联订单主表，确保订单与明细的对应关系；
      通过 LEFT JOIN 关联维度表（卖家、商品）及评价聚合子查询，避免因维度缺失导致数据行丢失；
      使用 CASE WHEN 动态判断配送状态（未知/延迟/准时）；
      在 WHERE 子句中通过子查询 raw.etl_log 表，动态筛选最新成功执行的 DWD 批次
      （load_batch_id），实现数据版本隔离与可追溯，确保视图仅展示最新有效数据；
      涉及表：dwd.fact_orders、dwd.fact_order_items、dwd.dim_sellers、
      dwd.dim_products、dwd.fact_order_reviews、raw.etl_log。
*/
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
