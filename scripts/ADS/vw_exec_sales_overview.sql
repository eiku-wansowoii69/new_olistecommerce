/*
脚本名称：vw_exec_sales_overview.sql
功能：创建应用数据层（ads schema）的卖家配送绩效视图（vw_seller_delivery_performance），
      通过关联 DWD 层的订单、订单明细、卖家、商品及评价表，整合出包含订单状态、配送时长、
      延迟情况、价格、运费及评分的宽表，用于支撑卖家配送绩效的看板分析。
说明：脚本使用 CREATE OR REPLACE VIEW 语句，支持重复运行（幂等）；视图以订单明细为粒度，
      通过 LEFT JOIN 关联维度表和聚合后的评价表，避免数据丢失；
      使用 CASE WHEN 动态计算 late_flag（准时/延迟/未知）字段；
      WHERE 子句通过 raw.etl_log 动态获取最新成功执行的 DWD 批次（load_batch_id），
      确保仅展示最新且完整的数据批次，实现数据版本隔离与可追溯。
      涉及表：dwd.fact_orders、dwd.fact_order_items、dwd.dim_sellers、
      dwd.dim_products、dwd.fact_order_reviews。
*/
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
