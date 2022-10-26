process BRACKEN_FILTER {
    tag "$bracken_report"
    label 'process_single'

    conda (params.enable_conda ? "bioconda::krakentools=1.2" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2--pyh5e36f6f_0':
        'quay.io/biocontainers/krakentools:1.2--pyh5e36f6f_0' }"

    input:
    tuple val(meta), path(bracken_report) 
    val exclude_taxa
    val include_taxa

    output: 
    tuple val(meta), path(filtered_bracken_report), emit: reports
    path "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:  
    def ex_taxa = exclude_taxa ? "--exclude ${exclude_taxa.join(' ')}" : ''
    def in_taxa = include_taxa ? "--include ${include_taxa.join(' ')}" : ''
    def args = task.ext.args ?: "${ex_taxa} ${in_taxa}"
    def prefix = task.ext.prefix ?: "${meta.id}"
    filtered_bracken_report = "${prefix}_filtered.tsv"
    def VERSION = '1.2'
    """
    filter_bracken.out.py -i '${bracken_report}' \\
        -o '${filtered_bracken_report}' \\
        ${args} 

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        krakentools: ${VERSION}

    END_VERSIONS
    """
}