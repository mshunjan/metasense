process BRACKEN_COMBINEBRACKENOUTPUTS {
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'mshunjan/bracken-plot:latest':
        'mshunjan/bracken-plot:latest' }"

    input:
    path unfiltered
    path filtered

    output:
    path "bracken_combined.tsv"       , emit: unfiltered
    path "bracken_combined.filtered.tsv"       , emit: filtered
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    // WARN: Version information not provided by tool on CLI.
    // Please update version string below when bumping container versions.
    def VERSION = '2.7'
    """
    combine_bracken_outputs.py \\
        $args \\
        --files ${unfiltered} \\
        -o bracken_combined.tsv

    combine_bracken_outputs.py \\
        $args \\
        --files ${filtered} \\
        -o bracken_combined.filtered.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        combine_bracken_output: ${VERSION}
    END_VERSIONS
    """
}
