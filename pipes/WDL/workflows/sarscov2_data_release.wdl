version 1.0

import "../tasks/tasks_ncbi_tools.wdl" as ncbi_tools


workflow sarscov2_data_release {
    meta {
        description: "Submit data bundles to databases and repositories"
        author: "Broad Viral Genomics"
        email:  "viral-ngs@broadinstitute.org"
    }

    input {
        File         ncbi_ftp_config_js
        File         genbank_xml
        File         genbank_zip
        #File         sra_meta_tsv
        #File         gisaid_csv
        #File         gisaid_fasta
        #Array[File]  cdc_stuff_also
        #File         cdc_s3_credentials
        String       ftp_path_prefix = basename(genbank_zip, ".zip")
        String       prod_test = "Production" # Production or Test
    }

    String prefix = "/~{prod_test}/~{ftp_path_prefix}"

    call ncbi_tools.ncbi_ftp_upload as genbank {
        input:
            config_js      = ncbi_ftp_config_js,
            submit_files   = [genbank_xml, genbank_zip],
            target_path    = "~{prefix}/genbank",
            wait_for       = "1"
    }

    # to do: Asymmetrik to impement an SRA tsv->xml conversion

    # to do: viral to implement a GISAID CLI upload task

    # to do: viral to implement S3 delivery task for CDC

    output {
        Array[File]    genbank_response   = genbank.reports_xmls
    }
}
