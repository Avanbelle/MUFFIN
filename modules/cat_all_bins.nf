process cat_all_bins {
    label 'ubuntu'
    input:
    set val(name), file(bins)
    output:
    set val(name) , file("all_bins.fa") 
    script:
    """
    cat ${bins} > all_bins.fa
    """
}