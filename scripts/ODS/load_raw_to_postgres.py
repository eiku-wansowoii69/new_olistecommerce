"""
脚本名称：raw 层数据导入脚本
功能：读取本地 CSV 文件目录下的 9 个 Olist 数据集文件，逐个导入到 PostgreSQL 的 raw schema 对应表中，并写入 ETL 日志。
说明：脚本采用函数式封装，主要包含 get_batch_id、log_start、log_end、load_one_file、load_all、main 六个函数；
每次运行通过 raw.batch_id_seq 生成一个唯一批次号 batch_id，为本次导入的所有数据打上批次标记；
每张表导入前先在 raw.etl_log 写入 running 记录，导入后更新为 success 或 failed，并记录行数和错误信息，日志 layer 字段固定为 'raw'；
数据导入使用 PostgreSQL COPY 协议（psycopg2 的 copy_expert），性能远高于逐行 INSERT；
每张表独立事务，单张表导入失败不影响其他表，实现按表粒度的隔离。
"""

import os
import time
from datetime import datetime
from io import StringIO

import pandas as pd
from sqlalchemy import create_engine, text


# ---------------- 配置 ----------------
DB_USER = "postgres"
DB_PASS = "***"
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "olistecommerce"
CSV_FOLDER = r"D:\31418\new_olistecommerce\datasets\raw"
TARGET_SCHEMA = "raw"
LOG_TABLE = "raw.etl_log"
BATCH_SEQ = "raw.batch_id_seq"


# ---------------- 工具函数 ----------------
def get_batch_id(engine):
    with engine.connect() as conn:
        bid = conn.execute(text(f"SELECT nextval('{BATCH_SEQ}')")).scalar()
        conn.commit()
    return bid


def log_start(engine, batch_id, table_name, source_file):
    with engine.connect() as conn:
        conn.execute(
            text(f"""
                INSERT INTO {LOG_TABLE}
                    (batch_id, table_name, source_file, layer, start_time, status)
                VALUES (:b, :t, :f, 'raw', :s, 'running')
            """),
            {"b": batch_id, "t": table_name, "f": source_file, "s": datetime.now()},
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


def load_one_file(engine, csv_path, table_name, batch_id):
    """导入单个 CSV 到 raw 表，返回行数。异常向上抛。"""
    df = pd.read_csv(csv_path, encoding="utf-8", dtype=str)

    # 补审计字段
    df["load_datetime"] = datetime.now()
    df["source_file"] = csv_path
    df["load_batch_id"] = batch_id

    # 序列化为 COPY 输入流
    buf = StringIO()
    df.to_csv(buf, index=False, header=False, sep="\t", na_rep="\\N")
    buf.seek(0)

    full_table = f"{TARGET_SCHEMA}.{table_name}"
    cols = ",".join(df.columns)

    raw_conn = engine.raw_connection()
    try:
        cur = raw_conn.cursor()
        cur.copy_expert(
            f"COPY {full_table} ({cols}) FROM STDIN "
            f"WITH (FORMAT CSV, DELIMITER E'\\t', NULL '\\N')",
            buf,
        )
        raw_conn.commit()
    finally:
        raw_conn.close()

    return len(df)


def load_all(engine, folder):
    """遍历目录下所有 CSV，逐表导入，逐表写日志。单表失败不影响其他表。"""
    for filename in sorted(os.listdir(folder)):
        if not filename.lower().endswith(".csv"):
            continue

        csv_path = os.path.join(folder, filename)
        table_name = filename[:-4]
        print(f"\n>>> 处理 {filename} -> {TARGET_SCHEMA}.{table_name}")

        log_start(engine, load_all.batch_id, table_name, csv_path)
        start = time.time()

        try:
            rows = load_one_file(engine, csv_path, table_name, load_all.batch_id)
            elapsed = round(time.time() - start, 2)
            print(f"    成功导入 {rows} 行，耗时 {elapsed}s")
            log_end(engine, load_all.batch_id, table_name, "success", rows)
        except Exception as e:
            print(f"    导入失败：{e}")
            log_end(engine, load_all.batch_id, table_name, "failed", 0, str(e))
            continue


# ---------------- 入口 ----------------
def main():
    engine = create_engine(
        f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}",
        pool_pre_ping=True,
    )

    batch_id = get_batch_id(engine)
    load_all.batch_id = batch_id
    print(f"当前批次 batch_id = {batch_id}")

    load_all(engine, CSV_FOLDER)
    print("\n全部 CSV 导入完成")


if __name__ == "__main__":
    main()
