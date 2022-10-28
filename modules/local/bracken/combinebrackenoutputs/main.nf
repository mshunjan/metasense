process BRACKEN_COMBINEBRACKENOUTPUTS {
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'mshunjan/bracken-plot:latest':
        'mshunjan/bracken-plot:latest' }"

    input:
    path input

    output:
    path "*.tsv"       , emit: result
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "bracken_combined.tsv"
    // WARN: Version information not provided by tool on CLI.
    // Please update version string below when bumping container versions.
    def VERSION = '2.7'
    """
    combine_bracken_outputs.py \\
        $args \\
        --files ${input} \\
        -o ${prefix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        combine_bracken_output: ${VERSION}
    END_VERSIONS
    """
}
