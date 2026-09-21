/*
脚本名称：raw 层初始化脚本
功能：初始化数据仓库的原始数据层（raw schema），包括 Olist 数据集 9 张原始表、批次号序列、ETL 日志表和批次索引。
说明：9 张业务表全部以 TEXT 类型存储字段，并在每张表末尾附加 3 个审计字段（load_datetime、source_file、load_batch_id），用于追踪每条数据的入库时间、来源文件和所属批次；
raw.batch_id_seq 用于为每次数据导入生成唯一批次号；raw.etl_log 记录每张表的加载状态、行数、耗时和错误信息，通过 layer 字段区分所属分层（raw/dwd/dws/ads）；
脚本使用 DROP TABLE IF EXISTS，执行会清空 raw 层所有数据，仅用于首次搭建或完全重置；如果只是新增字段，请改用 ALTER TABLE。
*/
-- =====================================================
-- raw 层初始化：建表（业务字段 + 审计字段）+ 日志表
-- =====================================================

-- 1. customers
DROP TABLE IF EXISTS raw.olist_customers_dataset;
CREATE TABLE raw.olist_customers_dataset (
    customer_id                 TEXT,
    customer_unique_id          TEXT,
    customer_zip_code_prefix    TEXT,
    customer_city               TEXT,
    customer_state              TEXT,
    load_datetime               TIMESTAMP,
    source_file                 TEXT,
    load_batch_id               BIGINT
);

-- 2. geolocation
DROP TABLE IF EXISTS raw.olist_geolocation_dataset;
CREATE TABLE raw.olist_geolocation_dataset (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             TEXT,
    geolocation_lng             TEXT,
    geolocation_city            TEXT,
    geolocation_state           TEXT,
    load_datetime               TIMESTAMP,
    source_file                 TEXT,
    load_batch_id               BIGINT
);

-- 3. orders
DROP TABLE IF EXISTS raw.olist_orders_dataset;
CREATE TABLE raw.olist_orders_dataset (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TEXT,
    order_approved_at               TEXT,
    order_delivered_carrier_date    TEXT,
    order_delivered_customer_date   TEXT,
    order_estimated_delivery_date   TEXT,
    load_datetime                   TIMESTAMP,
    source_file                     TEXT,
    load_batch_id                   BIGINT
);

-- 4. order_items
DROP TABLE IF EXISTS raw.olist_order_items_dataset;
CREATE TABLE raw.olist_order_items_dataset (
    order_id            TEXT,
    order_item_id       TEXT,
    product_id          TEXT,
    seller_id           TEXT,
    shipping_limit_date TEXT,
    price               TEXT,
    freight_value       TEXT,
    load_datetime       TIMESTAMP,
    source_file         TEXT,
    load_batch_id       BIGINT
);

-- 5. order_payments
DROP TABLE IF EXISTS raw.olist_order_payments_dataset;
CREATE TABLE raw.olist_order_payments_dataset (
    order_id                TEXT,
    payment_sequential      TEXT,
    payment_type            TEXT,
    payment_installments    TEXT,
    payment_value           TEXT,
    load_datetime           TIMESTAMP,
    source_file             TEXT,
    load_batch_id           BIGINT
);

-- 6. order_reviews
DROP TABLE IF EXISTS raw.olist_order_reviews_dataset;
CREATE TABLE raw.olist_order_reviews_dataset (
    review_id                   TEXT,
    order_id                    TEXT,
    review_score                TEXT,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        TEXT,
    review_answer_timestamp     TEXT,
    load_datetime               TIMESTAMP,
    source_file                 TEXT,
    load_batch_id               BIGINT
);

-- 7. products
DROP TABLE IF EXISTS raw.olist_products_dataset;
CREATE TABLE raw.olist_products_dataset (
    product_id                  TEXT,
    product_category_name       TEXT,
    product_name_lenght         TEXT,
    product_description_lenght  TEXT,
    product_photos_qty          TEXT,
    product_weight_g            TEXT,
    product_length_cm           TEXT,
    product_height_cm           TEXT,
    product_width_cm            TEXT,
    load_datetime               TIMESTAMP,
    source_file                 TEXT,
    load_batch_id               BIGINT
);

-- 8. sellers
DROP TABLE IF EXISTS raw.olist_sellers_dataset;
CREATE TABLE raw.olist_sellers_dataset (
    seller_id                   TEXT,
    seller_zip_code_prefix      TEXT,
    seller_city                 TEXT,
    seller_state                TEXT,
    load_datetime               TIMESTAMP,
    source_file                 TEXT,
    load_batch_id               BIGINT
);

-- 9. category translation
DROP TABLE IF EXISTS raw.product_category_name_translation;
CREATE TABLE raw.product_category_name_translation (
    product_category_name           TEXT,
    product_category_name_english   TEXT,
    load_datetime                   TIMESTAMP,
    source_file                     TEXT,
    load_batch_id                   BIGINT
);

-- 10. batch_id 序列
CREATE SEQUENCE IF NOT EXISTS raw.batch_id_seq;

-- 11. 日志表（含 layer 字段，用于区分 raw / dwd / dws 各层）
DROP TABLE IF EXISTS raw.etl_log;
CREATE TABLE raw.etl_log (
    batch_id        BIGINT,
    table_name      TEXT,
    source_file     TEXT,
    layer           TEXT,
    start_time      TIMESTAMP,
    end_time        TIMESTAMP,
    status          TEXT,
    rows_loaded     BIGINT,
    error_message   TEXT,
    PRIMARY KEY (batch_id, table_name)
);

-- 12. batch_id 索引
CREATE INDEX IF NOT EXISTS idx_customers_batch   ON raw.olist_customers_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_geolocation_batch ON raw.olist_geolocation_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_orders_batch      ON raw.olist_orders_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_order_items_batch ON raw.olist_order_items_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_payments_batch    ON raw.olist_order_payments_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_reviews_batch     ON raw.olist_order_reviews_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_products_batch    ON raw.olist_products_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_sellers_batch     ON raw.olist_sellers_dataset(load_batch_id);
CREATE INDEX IF NOT EXISTS idx_category_batch    ON raw.product_category_name_translation(load_batch_id);
