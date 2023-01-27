#!/usr/bin/env python

"""Provide functions to generate jupyter-reports."""

import argparse, os, sys
import nbformat as nbf
from nbconvert import HTMLExporter
from jinja2 import DictLoader
import papermill as pm
import yaml
from pathlib import Path

class ParseKwargs(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        setattr(namespace, self.dest, dict())
        for value in values:
            key, value = value.split("=")
            getattr(namespace, self.dest)[key] = value

def get_paths(dir, filepattern, order_dict=None):
    p = Path(dir)
    paths = list(p.glob(filepattern))
    if not order_dict:
        return [str(x) for x in paths]
    
    sorted_list = sorted(paths, key=lambda x: order_dict.get(x.name, float('inf')))
    return [str(x) for x in sorted_list]

def cell_combiner(nb, condition):
    to_combine = []
    for cell in nb.cells:
        if condition(cell):
            to_combine.append(cell)

    # Combine the cells
    combined_source = ""
    combined_metadata = []
    for cell in to_combine:
        combined_source += cell.source
        combined_metadata.append(cell.metadata)
        nb.cells.remove(cell)
    merged_cell_metadata = {}
    for cm in reversed(combined_metadata):
        merged_cell_metadata.update(cm)
    
    # Create and insert new cell
    new_cell = nbf.v4.new_code_cell(combined_source)
    new_cell.metadata = merged_cell_metadata
    nb.cells.insert(0, new_cell)

def book_combiner(paths):
    metadata = []
    merged = nbf.v4.new_notebook()
    
    for book in paths:
        nb = nbf.read(book, as_version=4)
        metadata.append(nb.metadata)
        merged.cells.extend(nb.cells)

        merged_metadata = {}
        for meta in reversed(metadata):
            merged_metadata.update(meta)
        merged.metadata = merged_metadata

    return merged        

def book_generator(inp, order=None):    
    if os.path.isdir(inp):
        paths = get_paths(inp, '*.ipynb', order)
        working_nb = book_combiner(paths)
    else: 
        working_nb = nbf.read(inp, as_version=4)

    return working_nb

def main():
    report_name = "report"
    prefix = "./"
    config = None
    order = None
    options = None
    output_nb = None
    parameters = []
    template = 'lab'
    inp = None

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-i", 
        "--input", 
        help="Single or directory of Jupyter Notebooks")

    parser.add_argument(
        "-p",
        "--parameters",
        nargs="*",
        action=ParseKwargs,
        help="Book parameters to pass at runtime",
    )
    parser.add_argument("-t", "--template", help="Report template")
    parser.add_argument("-c", "--config", help="Yaml configuration file")
    parser.add_argument("-o", "--output", help="Output directory")

    args = parser.parse_args()

    if args.input:
        inp = args.input
    else:
        sys.exit(1)
    
    if args.config:
        with open(args.config, 'r') as f:
            config = yaml.safe_load(f)
        order = config.get('order') if config.get('order') else order
        options = config.get('options') if config.get('options') else options
        report_name = config.get('report_name') if config.get('report_name') else report_name
        parameters = config.get('parameters') if config.get('parameters') else parameters

    if args.output:
        if not os.path.exists(args.output):
            os.mkdir(args.output)
        prefix = args.output
        if prefix[-1] != '/':
            prefix = prefix + '/'
        output_nb = prefix + report_name + ".ipynb"
    if args.parameters:
        parameters = args.parameters
    if args.template:
        template = args.template

    book = book_generator(inp, order=order)
    final_nb = book
    if parameters:
        cell_combiner(book,condition=(lambda x: True if x['metadata'].get('tags') and 'parameters' in x['metadata'].get('tags') else False))
        final_nb = pm.execute.execute_notebook(book, output_nb, parameters=parameters)
        
    
    if os.path.isfile(template):
        with open(template, "r") as t:
            template = t.read()
        dl = DictLoader({"template": template})
        html_exporter = HTMLExporter(extra_loaders=[dl], template_file="template")
    else:
        html_exporter = HTMLExporter(template_name="lab")

    if options:
        html_exporter.__dict__['_trait_values'].update(options)

    (body, resources) = html_exporter.from_notebook_node(
        final_nb, {"metadata": {"name": report_name}}
    )

    with open(f'{prefix}{report_name}.html', "w") as o:
        o.write(body)


if __name__ == "__main__":
    main()
