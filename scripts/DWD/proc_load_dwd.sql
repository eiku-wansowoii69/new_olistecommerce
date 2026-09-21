/*
脚本名称：DWD 层清洗与加载存储过程
功能：创建 9 个 PostgreSQL 存储过程，分别负责将 raw 层的原始数据清洗、类型转换后加载到 dwd 层对应的事实表和维度表。
说明：每个过程接收一个批次号参数 p_batch_id，先 TRUNCATE 目标表，再按批次过滤（WHERE load_batch_id = p_batch_id）从 raw 层读取数据；
清洗内容包括：TRIM 去除首尾空格、LOWER/UPPER/INITCAP 标准化文本大小写、NULLIF 将空字符串转为 NULL、CAST 将 TEXT 转换为 int/numeric/timestamp 等正确类型、COALESCE 填充默认值；
过程本身不写事务、不写日志，只负责数据搬运，事务控制和 etl_log 写入由调用方（Python 脚本 load_dwd.py）统一处理，保证全链路日志一致；
使用 CREATE OR REPLACE PROCEDURE，可重复执行覆盖旧定义；9 个过程命名规则为 dwd.load_{表名}，与 dwd 层的 9 张目标表一一对应。
*/

-- =====================================================
-- DWD 层：9 个存储过程
-- 只做 TRUNCATE + INSERT，事务和日志由 Python 控制
-- =====================================================

-- 1. fact_orders
CREATE OR REPLACE PROCEDURE dwd.load_fact_orders(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.fact_orders;

    INSERT INTO dwd.fact_orders
    (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        delivery_days,
        load_batch_id
    )
    SELECT DISTINCT --过滤两条一模一样的数据，正常情况下去重主键就行，但项目的原作者是这样写的，考虑到在这个项目下这种写法影响不大就保留了。
        order_id,
        customer_id,--ID仅需过滤空值和空格，但在业务层面这两个不可能为空
        LOWER(TRIM(order_status)) AS order_status,
        NULLIF(TRIM(order_purchase_timestamp), '')::timestamp AS order_purchase_timestamp,
        NULLIF(TRIM(order_approved_at), '')::timestamp AS order_approved_at,
        NULLIF(TRIM(order_delivered_carrier_date), '')::timestamp AS order_delivered_carrier_date,
        NULLIF(TRIM(order_delivered_customer_date), '')::timestamp AS order_delivered_customer_date,
        NULLIF(TRIM(order_estimated_delivery_date), '')::timestamp AS order_estimated_delivery_date,
        --增加字段（运输时间=客户收货日期-订单购买日期）
        NULLIF(TRIM(order_delivered_customer_date),'')::date - NULLIF(TRIM(order_purchase_timestamp),'')::date AS delivery_days,
        load_batch_id
    FROM raw.olist_orders_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 2. fact_order_items
CREATE OR REPLACE PROCEDURE dwd.load_fact_order_items(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.fact_order_items;

    INSERT INTO dwd.fact_order_items
    (
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value,
        load_batch_id
    )
    SELECT DISTINCT
        order_id,
        NULLIF(TRIM(order_item_id),'')::int AS order_item_id,
        product_id,
        seller_id,
        NULLIF(TRIM(shipping_limit_date),'')::timestamp AS shipping_limit_date,
        NULLIF(TRIM(price),'')::numeric(10,2) AS price,
        NULLIF(TRIM(freight_value),'')::numeric(10,2) AS freight_value,
        load_batch_id
    FROM raw.olist_order_items_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 3. dim_products
CREATE OR REPLACE PROCEDURE dwd.load_dim_products(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.dim_products;

    INSERT INTO dwd.dim_products
    (
        product_id,
        product_category_name,
        product_name_length,
        product_description_length,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm,
        load_batch_id
    )
    SELECT DISTINCT
        product_id,
        LOWER(TRIM(product_category_name)) AS product_category_name,
        NULLIF(TRIM(product_name_lenght),'')::numeric AS product_name_length,
        NULLIF(TRIM(product_description_lenght),'')::numeric AS product_description_length,--lenght这种是字段名本身错了，所以需要重新取别名
        NULLIF(TRIM(product_photos_qty),'')::numeric AS product_photos_qty,
        NULLIF(TRIM(product_weight_g),'')::numeric AS product_weight_g,
        NULLIF(TRIM(product_length_cm),'')::numeric AS product_length_cm,
        NULLIF(TRIM(product_height_cm),'')::numeric AS product_height_cm,
        NULLIF(TRIM(product_width_cm),'')::numeric AS product_width_cm,
        load_batch_id
    FROM raw.olist_products_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 4. dim_sellers
CREATE OR REPLACE PROCEDURE dwd.load_dim_sellers(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.dim_sellers;

    INSERT INTO dwd.dim_sellers
    (
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state,
        load_batch_id
    )
    SELECT DISTINCT
        seller_id,
        seller_zip_code_prefix,
        INITCAP(LOWER(TRIM(seller_city))) AS seller_city,--INITCAP()函数的作用是把该字符串各个首字母大写
        UPPER(TRIM(seller_state)) AS seller_state,
        load_batch_id
    FROM raw.olist_sellers_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 5. dim_customers
CREATE OR REPLACE PROCEDURE dwd.load_dim_customers(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.dim_customers;

    INSERT INTO dwd.dim_customers
    (
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
        load_batch_id
    )
    SELECT DISTINCT
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        INITCAP(LOWER(TRIM(customer_city))) AS customer_city,--统一将城市字段的首字母大写，保持一致性
        UPPER(TRIM(customer_state)) AS customer_state,
        load_batch_id
    FROM raw.olist_customers_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 6. fact_order_reviews
CREATE OR REPLACE PROCEDURE dwd.load_fact_order_reviews(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.fact_order_reviews;

    INSERT INTO dwd.fact_order_reviews
    (
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp,
        load_batch_id
    )
    SELECT DISTINCT
        review_id,
        order_id,
        NULLIF(TRIM(review_score),'')::int AS review_score,
        NULLIF(TRIM(review_comment_title),'') AS review_comment_title,
        NULLIF(TRIM(review_comment_message),'') AS review_comment_message,--评价的标题和内容也需要进行空格判断
        NULLIF(TRIM(review_creation_date),'')::timestamp AS review_creation_date,
        NULLIF(TRIM(review_answer_timestamp),'')::timestamp AS review_answer_timestamp,
        load_batch_id
    FROM raw.olist_order_reviews_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 7. fact_order_payments
CREATE OR REPLACE PROCEDURE dwd.load_fact_order_payments(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.fact_order_payments;

    INSERT INTO dwd.fact_order_payments
    (
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value,
        load_batch_id
    )
    SELECT DISTINCT
        order_id,
        NULLIF(TRIM(payment_sequential),'')::int AS payment_sequential,
        LOWER(TRIM(payment_type)) AS payment_type,
        COALESCE(NULLIF(TRIM(payment_installments),'')::int, 0) AS payment_installments,--分期付款期数，如果为空强制转换成0
        NULLIF(TRIM(payment_value),'')::numeric(10,2) AS payment_value,
        load_batch_id
    FROM raw.olist_order_payments_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 8. dim_geolocation
CREATE OR REPLACE PROCEDURE dwd.load_dim_geolocation(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.dim_geolocation;

    INSERT INTO dwd.dim_geolocation
    (
        geolocation_zip_code_prefix,
        latitude,
        longitude,
        geolocation_city,
        geolocation_state,
        load_batch_id
    )
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        NULLIF(TRIM(geolocation_lat),'')::numeric(9,6) AS latitude,
        NULLIF(TRIM(geolocation_lng),'')::numeric(9,6) AS longitude,
        INITCAP(LOWER(TRIM(geolocation_city))) AS geolocation_city,
        UPPER(TRIM(geolocation_state)) AS geolocation_state,
        load_batch_id
    FROM raw.olist_geolocation_dataset
    WHERE load_batch_id = p_batch_id;
END;
$$;


-- 9. dim_product_category
CREATE OR REPLACE PROCEDURE dwd.load_dim_product_category(p_batch_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE dwd.dim_product_category;

    INSERT INTO dwd.dim_product_category
    (
        product_category_name,
        product_category_name_english,
        load_batch_id
    )
    SELECT DISTINCT
        LOWER(TRIM(product_category_name)) AS product_category_name,
        INITCAP(LOWER(TRIM(product_category_name_english))) AS product_category_name_english,
        load_batch_id
    FROM raw.product_category_name_translation
    WHERE load_batch_id = p_batch_id;
END;
$$;
