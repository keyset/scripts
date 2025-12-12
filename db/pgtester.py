#!/bin/env python3

import asyncio
from datetime import datetime
import psycopg

connection_strings = [
    ""
]


def log_stuff(msg):
    print(f"{datetime.now().isoformat()} {msg}")


async def test_query(conninfo):
    result_version = None
    result_success = None
    query = """
    SELECT 1;
    """
    start = datetime.now()
    while (datetime.now() - start).total_seconds() < 5:
        try:
            async with await psycopg.AsyncConnection.connect(
                conninfo=conninfo
            ) as conn, conn.cursor() as cur:
                await cur.execute(query)
                await cur.fetchall()
                result_version = conn.info.server_version
                result_success = datetime.now()
        except (Exception, psycopg.DatabaseError):
            result_version = None
            break
        await asyncio.sleep(0.25)
    return result_version, result_success


async def do_the_thing(endpoint):
    conninfo = psycopg.conninfo.conninfo_to_dict(endpoint)
    current_version = None
    last_success = None
    while True:
        result_version, result_success = await test_query(endpoint)
        if current_version is None and result_version is None:
            log_stuff(f"{conninfo['host']} is dead")
        elif current_version is not None and result_version is None:
            last_success = result_success if result_success is not None else last_success
            log_stuff(f"{conninfo['host']} died! Last success was {last_success}")
        elif current_version is None and result_version is not None:
            log_stuff(f"Connected to {conninfo['host']} version {result_version}")
            current_version = result_version
            last_success = result_success
        elif current_version != result_version:
            log_stuff(f"{conninfo['host']} was upgraded to {result_version} in {(result_success - last_success).total_seconds()} seconds")
            last_success = result_success
            current_version = result_version
        elif current_version == result_version and result_success is not None:
            log_stuff(f"{conninfo['host']} is still alive on {result_version}.")
            last_success = result_success
            current_version = result_version

        await asyncio.sleep(0.25)


async def main():
    log_stuff("Starting...")
    futures = [do_the_thing(endpoint) for endpoint in connection_strings]
    await asyncio.gather(*futures)


asyncio.run(main())

