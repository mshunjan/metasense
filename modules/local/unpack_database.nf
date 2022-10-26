process UNPACK_DATABASE {
    tag "$database"
    label "process_single"

    input:
    path (database)

    output:
    path('kraken_db')                 , emit: db
    
    when:
    task.ext.when == null || task.ext.when

    script:
    """
    mkdir kraken_db
    tar xzvf "${database}" -C kraken_db
    
    """
}
