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