#!/usr/bin/env python

import os, argparse, sys, csv


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--input-path",
        dest="in_path",
        required=True,
        help="Directory containing submission files",
    )
    parser.add_argument(
        "-o",
        "--output-path",
        dest="out_path",
        required=True,
        help="Out directory for samplesheet",
    )

    args = parser.parse_args()

    path = os.path.abspath(args.in_path)
    # path = args.in_path
    sys.stdout.write("generating samples list\n")

    samples = {}
    for (dirpath, dirnames, filenames) in os.walk(path):
        for f in filenames:
            sample_name = f.split(".")[0]
            fpath = os.path.join(dirpath, f)
            if "_R" in sample_name:
                sample_name = sample_name.split("_R")[0]
            if sample_name in samples.keys():
                samples[sample_name].append(fpath)
            else:
                samples[sample_name] = [fpath]

    sys.stdout.write("generating sheet\n")

    sheet = []
    sheet_headers = ["sample", "fastq_1", "fastq_2"]

    for x in samples:
        record = {}
        record["sample"] = x
        if len(samples[x]) > 1:
            record["fastq_1"] = samples[x][0]
            record["fastq_2"] = samples[x][1]
        else:
            record["fastq_1"] = samples[x][0]
        sheet.append(record)

    with open(args.out_path, "w") as f:
        writer=csv.DictWriter(f, fieldnames=sheet_headers)
        writer.writeheader()
        writer.writerows(sheet)

    sys.stdout.write("sheet was generated succesfully\n")


if __name__ == "__main__":
    main()