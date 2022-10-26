#!/usr/bin/env python

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import os, argparse, sys


def load_pathogens(df, panel):
    pathogens = df[df[panel] == "Y"]["Name"].to_list()
    return pathogens


def subset_data(df, meta, panel):
    pathogens = load_pathogens(meta, panel)
    subset_df = df[df["Species"].str.lower().isin([x.lstrip().lower() for x in pathogens])]
    return subset_df


def get_panels(meta):
    panels = meta.loc[:, "CDC":"CNS"].columns.to_list()
    return panels


def get_data(path, sep):
    return pd.read_csv(filepath_or_buffer=path, sep=sep)


def visualize_data(df, outdir, metadata=None):
    # Drop unnecessary columns
    df.drop(columns=["taxonomy_id", "taxonomy_lvl"], inplace=True)
    df = df.loc[:, ~df.columns.str.contains("_num")]

    # Rename and melt columns
    new_columns = {"name": "Species", "variable": "Sample", "value": "Fraction Abundance"}
    new_df = df.melt(id_vars="name").rename(columns=new_columns)

    # Generate express chart and add traces to go plot
    figx = px.bar(new_df, x="Sample", y="Fraction Abundance", color="Species")
    fig = go.Figure(data=figx.data)

    if metadata:
        # Create dropdown menu
        buttons = []
        panels = get_panels(metadata)

        for p in panels:
            sub_df = subset_data(new_df, metadata, p).reset_index(drop=True)
            buttons.append(
                dict(
                    method="restyle",
                    label=p,
                    visible=True,
                    args=[
                        {"x": sub_df["Sample"].to_list(), "y": sub_df["Fraction Abundance"].to_list(), "type": "bar"},
                    ],
                )
            )

        # all option in menu
        buttons.insert(
            0,
            dict(
                method="restyle",
                label="All",
                visible=True,
                args=[
                    {"x": new_df["Sample"].to_list(), "y": new_df["Fraction Abundance"].to_list(), "type": "bar"},
                ],
            ),
        )

        # create update menu
        updatemenu = {
            "buttons": buttons,
            "direction": "down",
            "showactive": True,
        }

        fig.update_layout(
            updatemenus=[updatemenu],
        )

    fig.update_layout(
        barmode="stack",
        xaxis_title="Samples",
        yaxis_title="Fraction Abundance (%)",
    )
    # Save graph to file
    with open(outdir, "w") as f:
        f.write(fig.to_html(full_html=False, include_plotlyjs="cdn"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--data", nargs=2, help="Data for generating plot")

    parser.add_argument(
        "-m",
        "--metadata",
        nargs=2,
        help="MetaData for generating plot",
    )

    parser.add_argument("-o", "--outdir", dest="outdir", help="Output location")

    args = parser.parse_args()

    sys.stdout.write("Reading your data\n")

    data = get_data(args.data[0], args.data[1])
    outdir = args.outdir

    if ".html" not in args.outdir:
        raise argparse.ArgumentTypeError("must be an html file")

    if args.metadata:
        sys.stdout.write("Adding metadata\n")
        metadata = get_data(args.data[0], args.data[1])
        visualize_data(data, outdir, metadata)

    else:
        visualize_data(data, outdir)
    sys.stdout.write("Successfully created a plot!\n")


if __name__ == "__main__":
    main()
