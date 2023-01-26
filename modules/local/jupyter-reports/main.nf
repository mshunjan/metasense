process JUPYTER_REPORTS {
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'mshunjan/jupyter-reports:latest':
        'mshunjan/jupyter-reports:latest' }"

    input:
        path nbs
        path config
        path template
        val parameters

    output:
    path "report.html"    , emit: report

    when:
    task.ext.when == null || task.ext.when

    script:
    def template = template ? "-t ${template}" : ''
    def config = config ? "-c ${config}" : ''
    def args = task.ext.args ?: "${template} ${config}"

    """
    reports.py -i ${nbs} ${args}
    """
}
