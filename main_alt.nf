#!/usr/bin/env nextflow
nextflow.enable.dsl=2

log.info """
*********Start running MUFFIN*********
MUFFIN is a hybrid assembly and differential binning workflow for metagenomics, transcriptomics and pathway analysis.

If you use MUFFIN for your research please cite:

https://www.biorxiv.org/content/10.1101/2020.02.08.939843v1 

or

Van Damme R., Hölzer M., Viehweger A., Müller B., Bongcam-Rudloff E., Brandt C., 2020
"Metagenomics workflow for hybrid assembly, differential coverage binning, transcriptomics and pathway analysis (MUFFIN)",
doi: https://doi.org/10.1101/2020.02.08.939843 
**************************************
"""

include { helpMSG } from './functions.nf'
include { long_read_workflow } from './long.nf'
include { short_read_workflow } from './short.nf'
include { hybrid_workflow } from './hybrid.nf'

// Early exit and help message handling
if (params.help) { exit 0, helpMSG() }

// Error handling for execution profiles
if (!workflow.profile.matches(/^(?:local|sge|slurm|gcloud|ebi|lsf|git_action),(?:singularity|docker|conda)$/)) {
    exit 1, "Invalid execution profile. Please use -profile with a valid executer and engine combination, e.g., 'local,docker'."
}

// Modular inclusions based on parameters
def modulesToInclude = params.modular.tokenize('|')
modulesToInclude.each { module ->
    switch (module) {
        case "full":
        case "assemble":
        case "assem-class":
        case "assem-annot":
            include {sourmash_download_db} from './modules/sourmashgetdatabase'
            include {checkm_setup_db} from './modules/checkmsetupDB'
            include {checkm_download_db} from './modules/checkmgetdatabases'
            include {chopper} from './module/ont_qc' param(output: params.short_qc)
            include {merge} from './modules/ont_qc' params(output: params.output)
            include {fastp} from './modules/fastp' params(output: params.output)
            include {spades} from './modules/spades' params(output: params.output)
            include {spades_short} from './modules/spades' param(output: params.output)
            include {flye} from './modules/flye' params(output : params.output)
            include {minimap_polish} from'./modules/minimap2'
            include {racon} from './modules/polish'
            include {medaka} from './modules/polish' params(model : params.model)
            include {pilon} from './modules/polish' params(output : params.output)
            include {pilong} from './modules/polish' params(output : params.output)
            include {minimap2} from './modules/minimap2' //mapping for the binning 
            include {extra_minimap2} from './modules/minimap2'
            include {bwa} from './modules/bwa' //mapping for the binning
            include {extra_bwa} from './modules/bwa'
            include {metaquast} from './modules/quast'
            include {metabat2_extra} from './modules/metabat2' params(output : params.output)    
            include {metabat2} from './modules/metabat2' params(output : params.output)
            include {semibin2} from './modules/semibin2' params(output : params.output)
            include {comebin} from './modules/comebin' params(output : params.output)
            include {bam_merger} from './modules/samtools_merger' params(output : params.output)
            include {contig_list} from './modules/list_ids'
            include {cat_all_bins} from './modules/cat_all_bins'
            include {bwa_bin} from './modules/bwa'  
            include {minimap2_bin} from './modules/minimap2'
            include {metaquast} from './modules/quast' params(output : params.output)
            include {reads_retrieval} from './modules/seqtk_retrieve_reads' params(output : params.output)
            include {unmapped_retrieve} from './modules/seqtk_retrieve_reads' params(output : params.output)
            // Additional assembly and QC modules as needed
            break

        case "classify":
        case "class-annot":
            include {checkm} from './modules/checkm' params(output: params.output)
            include {sourmash_bins} from './modules/sourmash' params(output: params.output)
            include {sourmash_checkm_parser} from './modules/checkm_sourmash_parser' params(output: params.output)
            // CheckM and Sourmash DB download modules are included by default in assembly
            break

        case "annotate":
            include {eggnog_download_db} from './modules/eggnog_get_databases'
            include {eggnog_bin} from './modules/eggnog' params(output: params.output)
            include {fastp_rna} from './modules/fastp' params(output: params.output)
            include {de_novo_transcript_and_quant} from './modules/trinity_and_salmon' params(output: params.output)
            include {eggnog_rna} from './modules/eggnog' params(output: params.output)
            include {parser_bin_RNA} from './modules/parser' params(output: params.output)
            include {parser_bin} from './modules/parser' params(output: params.output)
            break
    }
}

// Always include readme and test modules
include {readme_output} from './modules/readme_output' params(output: params.output)
include {test} from './modules/test_data_dll'

workflow {

    // Validate assembler parameter
    if (!['metaflye', 'metaspades'].contains(params.assembler)) {
        error "--assembler: ${params.assembler} is invalid. Should be 'metaflye' or 'metaspades'."
    }

    if (!['short', 'long'].contains(params.readType)) {
    params.readType = 'hybride' // Définit 'hybride' comme valeur par défaut si 'short' ou 'long' n'est pas spécifié
    
    switch (params.readType) {
        case "short":
            short_read_workflow()
            break
        case "long":
            long_read_workflow()
            break
        default:
            hybrid_workflow()
    }

}
