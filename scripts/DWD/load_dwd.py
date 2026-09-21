"""
脚本名称：DWD 层数据加载脚本
功能：按顺序调用 dwd schema 下的 9 个存储过程，将 raw 层最新批次的原始数据清洗后加载到 dwd 层的事实表和维度表。
说明：脚本自动从 raw.etl_log 中获取最新成功的 raw 批次号，无需手动传参，保证 DWD 处理的数据与 raw 层最新批次一致；
每张表通过独立事务调用对应存储过程（with engine.begin()），成功自动提交、失败自动回滚，单表失败不影响后续表；
每次调用前后写入 raw.etl_log，日志 layer 字段固定为 'dwd'，与 raw 层日志共用同一张表，通过 layer 字段区分所属分层；
成功时记录目标表实际行数，失败时记录异常信息，实现全链路可追溯。
"""

import time
from datetime import datetime

from sqlalchemy import create_engine, text

DB_USER = "postgres"
DB_PASS = "***"
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "olistecommerce"
LOG_TABLE = "raw.etl_log"

engine = create_engine(
    f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}",
    pool_pre_ping=True,
)

# (过程名, 目标表名)
PROCEDURES = [
    ("dwd.load_dim_customers",        "dim_customers"),
    ("dwd.load_dim_sellers",          "dim_sellers"),
    ("dwd.load_dim_products",         "dim_products"),
    ("dwd.load_dim_product_category", "dim_product_category"),
    ("dwd.load_dim_geolocation",      "dim_geolocation"),
    ("dwd.load_fact_orders",          "fact_orders"),
    ("dwd.load_fact_order_items",     "fact_order_items"),
    ("dwd.load_fact_order_payments",  "fact_order_payments"),
    ("dwd.load_fact_order_reviews",   "fact_order_reviews"),
]


def get_latest_batch_id(engine):
    """取 raw 层最新成功批次的 batch_id"""
    with engine.connect() as conn:
        bid = conn.execute(
            text("""
                SELECT MAX(batch_id) FROM raw.etl_log
                WHERE layer = 'raw' AND status = 'success'
            """)
        ).scalar()
    return bid


def log_start(engine, batch_id, table_name):
    with engine.connect() as conn:
        conn.execute(
            text(f"""
                INSERT INTO {LOG_TABLE}
                    (batch_id, table_name, source_file, layer, start_time, status)
                VALUES (:b, :t, NULL, 'dwd', :s, 'running')
            """),
            {"b": batch_id, "t": table_name, "s": datetime.now()},
        )
        conn.commit()


def log_end(engine, batch_id, table_name, status, rows, err=None):
    with engine.connect() as conn:
        conn.execute(
            text(f"""
                UPDATE {LOG_TABLE}
                   SET end_time      = :e,
                       status        = :st,
                       rows_loaded   = :r,
                       error_message = :err
                 WHERE batch_id = :b
                   AND table_name = :t
                   AND layer = 'dwd'
            """),
            {
                "e": datetime.now(),
                "st": status,
                "r": rows,
                "err": err,
                "b": batch_id,
                "t": table_name,
            },
        )
        conn.commit()


def get_table_rows(engine, table_name):
    with engine.connect() as conn:
        n = conn.execute(text(f"SELECT count(*) FROM dwd.{table_name}")).scalar()
    return n


def main():
    batch_id = get_latest_batch_id(engine)
    if batch_id is None:
        print("raw.etl_log 里没有成功批次，无法执行 DWD")
        return
    print(f"当前批次 batch_id = {batch_id}")

    for proc_name, table_name in PROCEDURES:
        print(f"\n>>> CALL {proc_name} -> dwd.{table_name}")
        log_start(engine, batch_id, table_name)
        start = time.time()

        try:
            # 独立事务：成功自动 commit，失败自动 rollback
            with engine.begin() as conn:
                conn.execute(text(f"CALL {proc_name}(:b)"), {"b": batch_id})

            rows = get_table_rows(engine, table_name)
            elapsed = round(time.time() - start, 2)
            print(f"    成功 {rows} 行，耗时 {elapsed}s")
            log_end(engine, batch_id, table_name, "success", rows)
        except Exception as e:
            print(f"    失败：{e}")
            log_end(engine, batch_id, table_name, "failed", 0, str(e))
            continue

    print("\nDWD 层加载完成")


if __name__ == "__main__":
    main()
