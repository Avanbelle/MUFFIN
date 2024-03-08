workflow [long_read_workflow]{
    // Initialisation des variables pour les chemins des bases de données
    Channel database_sourmash

    // Configuration de la base de données Sourmash
    if (params.sourmash_db) { database_sourmash = file(params.sourmash_db) }
    else {
        sourmash_download_db() 
        database_sourmash = sourmash_download_db.out
    }   
    if (!params.checkm2db){
        // Vérification de l'existence du dossier et du fichier
        path_exists = file(params.db_path).exists() && file("${params.db_path}/${params.db_file}").exists()

        // Si le chemin n'existe pas ou si le fichier n'est pas trouvé.
        if( !path_exists | params.checkm2db_force_update) {
            checkm_download_db()
        } else {
            println "Le dossier et le fichier spécifié existent déjà."
        }
    }

    Channel ont_input_ch
    // Assemblage avec des reads longs (ONT)
    if (!params.ont) error "ONT reads path must be specified for 'long' read type."
    ont_input_ch = Channel.fromPath("${params.ont}/*.fastq{,.gz}", checkIfExists: true).map { file -> tuple(file.baseName, file) }
    if (!params.skip_ont_qc) {
        ont_input_ch = ont_input_ch.flatMap { chopper(it) }
    }

    Channel assembly_ch

    // Assemblage avec des reads longs (ONT) utilisant Flye
    flye(ont_input_ch)
    assembly_ch = flye.out

    assembly_ch.flatMap { contigs ->
        minimap_polish(contigs, ont_input_ch)
        }.flatMap { polished ->
            racon(polished)
        }.flatMap { racon_out ->
            medaka(racon_out)
        }.flatMap { medaka_out ->
            pilong(medaka_out, ont_input_ch, params.polish_iteration)
        }.set { assembly_ch }
        //ajouter pilon

    //*********
    // Mapping
    //*********
    
    // Mapping with Minimap2 for ONT reads
    Channel ont_bam_ch = assembly_ch
        .join(ont_input_ch)
        .map { assembly, reads -> [assembly, reads] }
        .flatMap { minimap2(it) }

    // Mapping additional ONT reads if specified
    if (params.extra_ont) {
        Channel ont_extra_bam_ch = assembly_ch
            .join(Channel.fromPath(params.extra_ont))
            .map { assembly, extraReads -> [assembly, extraReads] }
            .flatMap { extra_minimap2(it) }
    }

    //***************************************************
    // Assembly quality control
    //***************************************************
    if (params.reference) {
        //Channel ref_ch = params.reference
        Channel ref_ch = Channel.fromPath(params.reference)
        metaquast(assembly_ch, ref_ch)
        Channel metaquast_out_ch = metaquast.out
    }

    //***************************************************
    // Binning
    //***************************************************

    switch (params.bintool) {
        case 'metabat2':
            if (params.extra_ont || params.extra_ill ) { // check if differential coverage binning possible
                metabat2_ch = ont_bam_ch.join(extra_bam)
                bam_merger(metabat2_ch)
                metabat2_extra(assembly_ch, bam_merger.out)
                metabat2_out = metabat2_extra.out
            }
            else {
                metabat2_ch = assembly_ch.join(ont_bam_ch)
                metabat2(metabat2_ch)
                metabat2_out = metabat2.out
            }
            break

        case 'semibin2':
            Channel semibin2_ch = assembly_ch.join(ont_bam_ch)
            semibin2(semibin2_ch)
            Channel semibin2_out = semibin2.out
            break

        case 'comebin':
            Channel comebin_ch = assembly_ch.join(ont_bam_ch)
            comebin(comebin_ch)
            Channel comebin_out = comebin.out
            break

        default:
            println "L'outil spécifié (${params.bintool}) n'est pas reconnu. Utilisation de l'outil par défaut: metabat2"
            if (params.extra_ont || params.extra_ill ) { // check if differential coverage binning possible
                metabat2_ch = ont_bam_ch.join(extra_bam)
                bam_merger(metabat2_ch)
                metabat2_extra(assembly_ch, bam_merger.out)
                metabat2_out = metabat2_extra.out
            }
            else {
                metabat2_ch = assembly_ch.join(ont_bam_ch)
                metabat2(metabat2_ch)
                metabat2_out = metabat2.out
            }
            
    }


    if (params.modular=="full" | params.modular=="classify" | params.modular=="assem-class" | params.modular=="class-annot") {

        //**************
        // File handling
        //**************

        //bins (list with id (run id not bin) coma path/to/file)
        if (params.bin_classify) { 
            classify_ch = Channel
                .fromPath( params.bin_classify, checkIfExists: true )
                .splitCsv()
                .map { row -> ["${row[0]}", file("${row[1]}", checkIfExists: true)]  }
                .view()
                }


        //merge every bining tool result
        else {classify_ch= metabat2_out_ch.join(semibin2_out_ch).join(comebin_out_ch)}

        // if (params.modular=="classify" | params.modular=="class-annot") {
        //     // sourmash_db
        //     if (params.sourmash_db) { database_sourmash = file(params.sourmash_db) }
        //     else {
        //         sourmash_download_db() 
        //         database_sourmash = sourmash_download_db.out
        //     }   
        //     if (!params.checkm2db){
        //         // Vérification de l'existence du dossier et du fichier
        //         path_exists = file(params.db_path).exists() && file("${params.db_path}/${params.db_file}").exists()

        //         // Si le chemin n'existe pas ou si le fichier n'est pas trouvé.
        //         if( !path_exists | params.checkm2db_force_update) {
        //             checkm_download_db()
        //         } else {
        //             println "Le dossier et le fichier spécifié existent déjà."
        //         }
        //     }
        // }
    }
    //*************************
    // Bins classify workflow
    //*************************

    //checkm of the final assemblies
    //checkm(classify_ch.groupTuple(by:0)) //checkm QC of the bins
    checkm2(classify_ch)
    Channel checkm2_out_ch = checkm2.out 

    //sourmash classification using gtdb database
    sourmash_bins(classify_ch,database_sourmash) // fast classification using sourmash with the gtdb (not the best classification but really fast and good for primarly result)
    sourmash_checkm_parser(checkm.out[0],sourmash_bins.out.collect()) //parsing the result of sourmash and checkm in a single result file
    
}



