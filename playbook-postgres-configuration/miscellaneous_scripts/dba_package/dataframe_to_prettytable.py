from prettytable import PrettyTable
import pandas as pd

def dataframe_to_prettytable(df: pd.DataFrame) -> PrettyTable:
    """
    Converts a pandas DataFrame to a PrettyTable object.

    Parameters:
        df (pd.DataFrame): The DataFrame to convert.

    Returns:
        PrettyTable: The converted PrettyTable object.
    """
    pt = PrettyTable()
    pt.field_names = df.columns.tolist()

    for _, row in df.iterrows():
        pt.add_row(row.tolist())

    return pt