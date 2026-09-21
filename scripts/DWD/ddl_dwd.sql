/*
脚本名称：DWD 层建表脚本
功能：创建数据仓库明细层（dwd schema），采用星型模型构建 Olist 电商数据集的事实表和维度表，用于存储经过清洗、类型转换和标准化后的明细数据。
说明：脚本使用 IF NOT EXISTS 判等判断，表已存在时跳过，可重复运行；共 9 张表，分为 4 张事实表（fact_orders、fact_order_items、fact_order_payments、fact_order_reviews）和 5 张维度表（dim_customers、dim_sellers、dim_products、dim_product_category、dim_geolocation）；
每张表末尾均附加 load_batch_id 字段，记录数据来自哪一批 raw 数据，实现全仓库数据可追溯；所有表按 load_batch_id 建立索引，加速后续按批次过滤和下游 DWS/ADS 层的查询；
事实表存储订单主表、订单商品明细、支付明细和评价明细，维度表存储客户、卖家、商品、商品类目和地理位置信息，便于后续多维度关联分析。
*/
CREATE SCHEMA IF NOT EXISTS dwd;

-- ============ 事实表 ============

CREATE TABLE IF NOT EXISTS dwd.fact_orders (
    order_id text,--在olist里的ID是32 位十六进制字符串，采用文本类型
    customer_id text,
    order_status text,
    order_purchase_timestamp timestamp,
    order_approved_at timestamp,
    order_delivered_carrier_date timestamp,
    order_delivered_customer_date timestamp,
    order_estimated_delivery_date timestamp,
    delivery_days int,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.fact_order_items (
    order_id text,
    order_item_id int,--这个字段名是单一数字，用int类型
    product_id text,
    seller_id text,
    shipping_limit_date timestamp,
    price numeric,
    freight_value numeric,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.fact_order_payments (
    order_id text,
    payment_sequential int,
    payment_type text,
    payment_installments int,
    payment_value numeric(10,2),
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.fact_order_reviews (
    review_id text,
    order_id text,
    review_score int,
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp,
    review_answer_timestamp timestamp,
    load_batch_id bigint
);

-- ============ 维度表 ============

CREATE TABLE IF NOT EXISTS dwd.dim_customers (
    customer_id text,
    customer_unique_id text,
    customer_zip_code_prefix text,
    customer_city text,
    customer_state text,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.dim_sellers (
    seller_id text,
    seller_zip_code_prefix text,--邮编用text格式最合适
    seller_city text,
    seller_state text,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.dim_products (
    product_id text,
    product_category_name text,
    product_name_length numeric,
    product_description_length numeric,
    product_photos_qty numeric,
    product_weight_g numeric,
    product_length_cm numeric,
    product_height_cm numeric,
    product_width_cm numeric,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.dim_product_category (
    product_category_name text,
    product_category_name_english text,
    load_batch_id bigint
);

CREATE TABLE IF NOT EXISTS dwd.dim_geolocation (
    geolocation_zip_code_prefix text,
    latitude numeric,
    longitude numeric,
    geolocation_city text,
    geolocation_state text,
    load_batch_id bigint
);

-- ============ 索引 ============

CREATE INDEX IF NOT EXISTS idx_fact_orders_batch       ON dwd.fact_orders(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_fact_order_items_batch  ON dwd.fact_order_items(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_fact_payments_batch     ON dwd.fact_order_payments(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_fact_reviews_batch      ON dwd.fact_order_reviews(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_dim_customers_batch     ON dwd.dim_customers(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_dim_sellers_batch       ON dwd.dim_sellers(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_dim_products_batch      ON dwd.dim_products(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_dim_category_batch      ON dwd.dim_product_category(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_dim_geolocation_batch   ON dwd.dim_geolocation(load_batch_id);
