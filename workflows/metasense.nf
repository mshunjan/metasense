/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowMetasense.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.kraken_db, params.metadata ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.kraken_db) { } else { exit 1, 'Kraken database is required!' }

// Optional parameters
if (params.metadata) {ch_metadata = file(params.metadata)} else {ch_metadata = 'NO_FILE'}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK } from '../subworkflows/local/input_check'
include { SAMPLESHEET_GENERATE } from '../modules/local/samplesheet_generate'
include { UNPACK_DATABASE } from '../modules/local/unpack_database'
include { BRACKEN_FILTER } from '../modules/local/bracken/filter/main'
include { BRACKEN_COMBINEBRACKENOUTPUTS } from '../modules/local/bracken/combinebrackenoutputs/main'
include { BRACKEN_PLOT } from '../modules/local/bracken/plot/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTP                         } from '../modules/nf-core/fastp/main'
include { MULTIQC                       } from '../modules/nf-core/multiqc/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS   } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { KRAKEN2_KRAKEN2               } from '../modules/nf-core/kraken2/kraken2/main'
include { BRACKEN_BRACKEN               } from '../modules/nf-core/bracken/bracken/main'
include { SEQTK_SAMPLE                  } from '../modules/nf-core/seqtk/sample/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []

workflow METASENSE {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    if (file(params.input).isDirectory()) { 
        ch_dir = file(params.input)
        SAMPLESHEET_GENERATE (
            ch_dir
        )
        ch_samplesheet = SAMPLESHEET_GENERATE.out.csv
        ch_versions = ch_versions.mix(SAMPLESHEET_GENERATE.out.versions)
        }
    else {
        ch_samplesheet = file(params.input) 
    }

    INPUT_CHECK (
        ch_samplesheet
    )
    ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)
    if (params.subsample){ 
        ch_subsample_frac = params.subsample

        SEQTK_SAMPLE (
            INPUT_CHECK.out.reads,
            ch_subsample_frac
        )
        ch_reads = SEQTK_SAMPLE.out.reads
        
        }
    else {
        ch_reads = INPUT_CHECK.out.reads
    }

    //
    // MODULE: Run QC
    //
    if (params.qc) {
        adapter_fasta = []
        save_trimmed_fail = false
        save_merged = false
        FASTP (
            ch_reads,
            adapter_fasta,
            save_trimmed_fail,
            save_merged
        )
        ch_reads = FASTP.out.reads
        ch_versions = ch_versions.mix(FASTP.out.versions.first()) 
    }
    
    //
    // MODULE: Run Kraken2
    //

    if (file(params.kraken_db).isDirectory()) {
        ch_kraken_db = file(params.kraken_db) 
    }
    else {
        file_url = file(params.kraken_db)
        UNPACK_DATABASE(
            file_url
        )
        ch_kraken_db = UNPACK_DATABASE.out.db
    }

    save_output_fastqs = false
    save_reads_assignment = false
  
    KRAKEN2_KRAKEN2 (
        ch_reads,
        ch_kraken_db,
        save_output_fastqs,
        save_reads_assignment
    )
    ch_versions = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions.first())

    //
    // MODULE: Run Bracken
    //

    BRACKEN_BRACKEN (
        KRAKEN2_KRAKEN2.out.report,
        ch_kraken_db
    )

    ch_versions = ch_versions.mix(BRACKEN_BRACKEN.out.versions.first())

    // 
    // MODULE: Filter Bracken
    // 

    // excluding human taxa from abundance measurement
    exclude_taxa = [9606]
    include_taxa = false

    BRACKEN_FILTER (
        BRACKEN_BRACKEN.out.reports,
        exclude_taxa,
        include_taxa
    )

    ch_versions = ch_versions.mix(BRACKEN_FILTER.out.versions.first())

    // 
    // MODULE: Combine Bracken Outputs
    // 

    BRACKEN_COMBINEBRACKENOUTPUTS (
       BRACKEN_BRACKEN.out.reports.collect{it[1]},
       BRACKEN_FILTER.out.reports.collect{it[1]}
    )

    ch_versions = ch_versions.mix(BRACKEN_COMBINEBRACKENOUTPUTS.out.versions)

    //
    // Module: Plot bracken data 
    // 
    BRACKEN_PLOT (
        BRACKEN_COMBINEBRACKENOUTPUTS.out.filtered
    )
    ch_versions = ch_versions.mix(BRACKEN_PLOT.out.versions)


    // Dump softwares
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowMetasense.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    methods_description    = WorkflowMetasense.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description)
    ch_methods_description = Channel.value(methods_description)

    ch_multiqc_files = Channel.empty()
    // ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    // ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(BRACKEN_COMBINEBRACKENOUTPUTS.out.filtered.collect())
    ch_multiqc_files = ch_multiqc_files.mix(BRACKEN_PLOT.out.graph.collect())

    if (params.qc) {
        ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json.collect{it[1]}.ifEmpty([]))
        // ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    }

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.collect().ifEmpty([]),
        ch_multiqc_custom_config.collect().ifEmpty([]),
        ch_multiqc_logo.collect().ifEmpty([])
    )
    multiqc_report = MULTIQC.out.report.toList()
    ch_versions    = ch_versions.mix(MULTIQC.out.versions)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.adaptivecard(workflow, params, summary_params, projectDir, log)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
