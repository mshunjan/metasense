process BRACKEN_PLOT {
    tag "$combined_bracken_report"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'mshunjan/bracken-plot':
        'mshunjan/bracken-plot' }"

    input:
    path(combined_bracken_report) 
    // path(metadata)

    output: 
    path(plot_name)                                 , emit: graph
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:  
    def args = task.ext.args ?: ""

    def data_sep = '"\t"'
    def meta_sep = ','
    // def add_meta = metadata.name != 'NO_FILE' ? "-m ${metadata} ${meta_sep}": ""
    
    plot_name = "graph.html"
    
    def VERSION = '0.1'
    """
    plot_bracken.py -i ${combined_bracken_report} $data_sep -o ${plot_name}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        plot_bracken: ${VERSION}

    END_VERSIONS
    """
}