def flatten_df(nested_df):
    flat_cols = [c[0] for c in nested_df.dtypes if (c[1][:6] != 'struct' or c[1][:6] == 'struct')]
    print(flat_cols)
    nested_cols = [c[0] for c in nested_df.dtypes if c[1][:12] == 'array<struct']
    print(nested_cols)
    for i in range(len(nested_cols)):
        col_name = nested_cols[i]
        print(col_name)
        flat_df = nested_df.select(flat_cols + [explode_outer(nested_df[col_name]).alias(col_name+'_'+'col')])
        flat_df = flat_df.select(flat_cols + [col_name+'_'+'col'+'.*'])
        flat_df = flat_df.drop(col(col_name))
    return flat_df