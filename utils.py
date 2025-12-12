from prettytable import PrettyTable
from pipe import Pipe


@Pipe
def table_output(iterable, *fields):
    snap_table = PrettyTable(field_names=fields)
    snap_table.add_rows(
        [[the_thing[field] for field in fields] for the_thing in iterable]
    )
    return snap_table


def wait_for(wait_func, wait_for_value, wait_time, max_iters):
    current_value = None
    iters = 0
    while current_value != wait_for_value:
        new_value = wait_func()
        iters += 1
        if new_value != current_value:
            print(f"{datetime.utcnow().isoformat()} currently {new_value}")
            current_value = new_value
        elif iters > max_iters:
            break
        sleep(wait_time)
