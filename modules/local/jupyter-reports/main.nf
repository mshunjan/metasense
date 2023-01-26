process JUPYTER_REPORTS {
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'mshunjan/jupyter-reports:latest':
        'mshunjan/jupyter-reports:latest' }"

    input:
    path  input_files, stageAs: "?/*"
    path(nbs)
    path(parameters) 
    path(config)
    path(template)

    output:
    path "report.html"    , emit: report

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    template 'reports.py'
}
