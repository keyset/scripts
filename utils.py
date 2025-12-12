from prettytable import PrettyTable
from pipe import Pipe


@Pipe
def table_output(iterable, *fields):
    snap_table = PrettyTable(field_names=fields)
    snap_table.add_rows(
        [[the_thing[field] for field in fields] for the_thing in iterable]
    )
    return snap_table
