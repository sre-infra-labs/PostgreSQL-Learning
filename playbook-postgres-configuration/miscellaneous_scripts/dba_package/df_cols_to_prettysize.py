import pandas as pd

def get_pretty_data_size(size:float, unit:str='mb', precision:int=2):
    """_summary_

    Args:
        size (float): _description_
        unit (str, optional): _description_. Defaults to 'mb'.
        precision (int, optional): _description_. Defaults to 2.

    Returns:
        _type_: _description_

    Examples:
        pt.custom_format = { "free_memory_kb": lambda field, value: self.get_pretty_data_size(int(value),'kb') }
        pt.custom_format["threshold_kb"] = lambda field, value: self.get_pretty_data_size(int(value),'kb')
    """

    if size is None:
        return f"None"

    unit = unit.lower()
    suffixes = ['b', 'kb', 'mb', 'gb', 'tb']
    suffixIndex = suffixes.index(unit)
    while size > 1024 and suffixIndex < (len(suffixes)-1):
        suffixIndex += 1 #increment the index of the suffix
        size = size/1024.0 #apply the division

    return "%.*f %s"%(precision,size,suffixes[suffixIndex])

def df_cols_to_prettysize(df, columns_list, input_size='mb'):
    """
    Convert specified columns in a DataFrame from current_unit to human-readable file sizes.

    Parameters:
        df (pd.DataFrame): The DataFrame containing size values.
        columns_list (list): List of column names to convert.
        current_unit (str): The current unit of the data ('kb', 'mb', 'gb').

    Returns:
        pd.DataFrame: Modified DataFrame with human-readable sizes in specified columns.
    """

    input_size = input_size.lower()
    suffixes = ['b', 'kb', 'mb', 'gb', 'tb']

    # Transform column names
    columns_all = list(df.columns)
    columns_meta = list()

    for col in columns_all:
        suffix_identified = False

        col_unit = None
        col_new_name = col

        for unit in suffixes:
            # print(f"Col: {col} || unit: {unit}")
            if col.endswith(f"_{unit}"):
                suffix_identified = True
                col_unit = unit
                col_new_name = col.replace(f"_{unit}", '')
                break

        if col in columns_list:
            if suffix_identified:
                columns_meta.append(dict(action=True, col_name=col, new_name=col_new_name, unit=col_unit))
            else:
                columns_meta.append(dict(action=True, col_name=col, new_name=col_new_name, unit=input_size))
        else:
            columns_meta.append(dict(action=False, col_name=col, new_name=col_new_name, unit=input_size))

    # Create empty dataframe
    df_new = pd.DataFrame()
    for col_dict in columns_meta:
        print(f"col_dict: {col_dict}")
        if col_dict['action']:
            df_new[col_dict['new_name']] = df[col_dict['col_name']].apply(lambda val: get_pretty_data_size(val, col_dict['unit']))
        else:
            df_new[col_dict['new_name']] = df[col_dict['col_name']]

    return df_new

    # unit_multipliers = {
    #     'kb': 1,
    #     'mb': 1024,
    #     'gb': 1024 ** 2,
    # }

    # current_unit = current_unit.lower()
    # if current_unit not in unit_multipliers:
    #     raise ValueError(f"Unsupported current_unit: {current_unit}. Must be one of {list(unit_multipliers.keys())}.")

    # base = unit_multipliers[current_unit]

    # def human_readable(size_in_kb):
    #     if pd.isna(size_in_kb) or size_in_kb < 0:
    #         return "N/A"
    #     idx = 0
    #     while size_in_kb >= 1024 and idx < len(suffixes) - 1:
    #         size_in_kb /= 1024.0
    #         idx += 1
    #     return f"{round(size_in_kb, 1)} {suffixes[idx]}"

    # # Apply transformation using .loc to avoid SettingWithCopyWarning
    # for col in columns_list:
    #     df.loc[:, col] = pd.to_numeric(df[col], errors='coerce')
    #     # df.loc[:, col] = (df[col] * base).apply(human_readable)
    #     df.loc[:, col] = (df[col] * base).apply(human_readable).astype("object")
