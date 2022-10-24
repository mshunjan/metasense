import pandas as pd
import os, argparse, sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input-path', dest='in_path', required=True, help='Directory containing submission files')
    parser.add_argument('-o', '--output-path', dest='out_path', required=True, help='Out directory for samplesheet')

    args = parser.parse_args()
    
    # path = os.path.abspath(args.in_path)
    path = args.in_path
    sys.stdout.write("generating samples list\n")

    samples = {}
    for (dirpath, dirnames, filenames) in os.walk(path):
        for f in filenames:
            sample_name = f.split('_')[0]
            fpath = (os.path.join(dirpath,f))

            if sample_name in samples.keys():
                samples[sample_name].append(fpath)
            else:
                samples[sample_name] = [fpath]
    
    sys.stdout.write("generating sheet\n") 

    sheet = []
    sheet_headers = ['sample', 'fastq_1', 'fastq_2']

    for x in samples:
        record = {}
        record['sample'] = x
        if len(samples[x]) > 1:
            record['fastq_1'] = samples[x][0]
            record['fastq_2'] = samples[x][1]
        else:
            record['fastq_1'] = samples[x][0]
        sheet.append(record)

    df = pd.DataFrame(sheet, columns=sheet_headers)
    df.set_index('sample', inplace=True)
    df.to_csv(args.out_path)
    
    sys.stdout.write("sheet was generated succesfully\n")

if __name__ == "__main__":
    main()
