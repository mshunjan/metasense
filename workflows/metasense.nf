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

ch_jpreport_nbs = Channel.fromPath("$projectDir/assets/notebooks", checkIfExists: true)
ch_jpreport_config = Channel.fromPath("$projectDir/assets/jupyter_reports_config.yml", checkIfExists: true)
ch_jpreport_template = params.jpreport_template ? Channel.fromPath( params.jpreport_template, checkIfExists: true ) : Channel.empty()

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
include { JUPYTER_REPORTS } from '../modules/local/jupyter-reports/main'

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

def jpreports = []

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

    ch_filtered_bracken_files = BRACKEN_FILTER.out.reports.collect{it[1]}

    BRACKEN_COMBINEBRACKENOUTPUTS (
        ch_filtered_bracken_files
    )

    ch_versions = ch_versions.mix(BRACKEN_COMBINEBRACKENOUTPUTS.out.versions)

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

    ch_jpreports_files = Channel.empty()
    ch_jpreports_files = ch_jpreports_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_jpreports_files = ch_jpreports_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_jpreports_files = ch_jpreports_files.mix(BRACKEN_COMBINEBRACKENOUTPUTS.out.result.collect())


    if (params.qc) {
        ch_jpreports_files = ch_multiqc_files.mix(FASTP.out.json.collect{it[1]}.ifEmpty([]))
    }
    
    parameters = [brac_file:"bracken_combined.tsv", sv_file:"software_versions.yml"]

    JUPYTER_REPORTS (
        ch_jpreports_files.collect(),
        ch_jpreport_nbs.collect().ifEmpty([]),
        parameters,
        ch_jpreport_config.collect().ifEmpty([]),
        ch_jpreport_template.collect().ifEmpty([]) 
    )

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
