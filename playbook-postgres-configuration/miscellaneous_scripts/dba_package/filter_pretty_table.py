from prettytable import PrettyTable

def filter_pretty_table(pt: PrettyTable, filters: list[callable]) -> PrettyTable:
    rows = pt._rows.copy()
    for f in filters:
        rows = list(filter(f, rows))

    new_pt = PrettyTable()
    new_pt.field_names = pt.field_names
    for row in rows:
        new_pt.add_row(row)
    return new_pt