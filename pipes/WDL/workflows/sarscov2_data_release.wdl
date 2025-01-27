version 1.0

import "../tasks/tasks_ncbi_tools.wdl" as ncbi_tools
import "../tasks/tasks_sarscov2.wdl" as sarscov2
import "../tasks/tasks_terra.wdl" as terra
import "../tasks/tasks_utils.wdl" as utils

workflow sarscov2_data_release {
    meta {
        description: "Submit data bundles to databases and repositories"
        author: "Broad Viral Genomics"
        email:  "viral-ngs@broadinstitute.org"
    }

    input {
        String       flowcell_id

        File?        ncbi_ftp_config_js
        File         genbank_xml
        File         genbank_zip
        File         sra_meta_tsv
        String       sra_bioproject
        String       sra_data_bucket_uri

        File?        gisaid_auth_token
        File?        gisaid_csv
        File?        gisaid_fasta

        String?      gcs_out_reporting

        File?        cdc_s3_credentials
        File?        cdc_passing_fasta
        File?        cdc_final_metadata
        File?        cdc_cumulative_metadata
        Array[File]  cdc_aligned_trimmed_bams
        String?      cdc_s3_uri

        String?      dashboard_bucket_uri

        String       ftp_path_prefix = basename(genbank_zip, ".zip")
        String       prod_test = "Production" # Production or Test
    }

    String prefix = "/~{prod_test}/~{ftp_path_prefix}"

    if (defined(ncbi_ftp_config_js)) {
        # publish to NCBI Genbank
        call ncbi_tools.ncbi_sftp_upload as genbank_upload {
            input:
                config_js        = select_first([ncbi_ftp_config_js]),
                submission_xml   = genbank_xml,
                additional_files = [genbank_zip],
                target_path      = "~{prefix}/genbank",
                wait_for         = "1"
        }

        # publish to NCBI SRA
        call ncbi_tools.sra_tsv_to_xml {
            input:
                meta_submit_tsv  = sra_meta_tsv,
                config_js        = select_first([ncbi_ftp_config_js]),
                bioproject       = sra_bioproject,
                data_bucket_uri  = "~{sra_data_bucket_uri}/~{flowcell_id}"
        }
        call ncbi_tools.ncbi_sftp_upload as sra_upload {
            input:
                config_js        = select_first([ncbi_ftp_config_js]),
                submission_xml   = sra_tsv_to_xml.submission_xml,
                additional_files = [],
                target_path      = "~{prefix}/sra",
                wait_for         = "1"
        }
    }

    # publish to GISAID
    if (defined(gisaid_auth_token)) {
        call sarscov2.gisaid_uploader {
            input:
                gisaid_sequences_fasta = select_first([gisaid_fasta]),
                gisaid_meta_csv        = select_first([gisaid_csv]),
                cli_auth_token         = select_first([gisaid_auth_token])
        }
    }

    # deliver to dashboard bucket ingest
    if (defined(cdc_cumulative_metadata) && defined(dashboard_bucket_uri)) {
        call utils.tsv_drop_cols as meta_sanitize {
            input:
                in_tsv = select_first([cdc_cumulative_metadata]),
                drop_cols = ['internal_id','collaborator_id','matrix_id','hl7_message_id'],
                out_filename = "metadata-cumulative.txt"
        }
        call terra.gcs_copy as dashboard_delivery {
            input:
                infiles = [meta_sanitize.out_tsv],
                gcs_uri_prefix = select_first([dashboard_bucket_uri])
        }
    }

    # deliver to State Public Health Epis
    if(defined(gcs_out_reporting) && defined(cdc_final_metadata)) {
        call utils.tsv_to_csv as meta_final_csv {
          input:
            tsv = select_first([cdc_final_metadata])
        }
        call terra.gcs_copy as gcs_reporting_dump {
            input:
              infiles        = [meta_final_csv.csv],
              gcs_uri_prefix = "~{gcs_out_reporting}/"
        }
    }

    # deliver to CDC
    if (defined(cdc_s3_credentials)) {
        call utils.today {
            input: timezone = "America/New_York"  # CDC is based in Atlanta
        }

        String s3_prefix = "~{cdc_s3_uri}/~{today.date}/~{flowcell_id}"
        call utils.make_empty_file as upload_complete {
            input:
                out_filename = "uploadcomplete.txt"
        }
        if (defined(cdc_cumulative_metadata)) {
            call utils.rename_file as cumulative_meta_tsv {
                input:
                    infile = select_first([cdc_cumulative_metadata]),
                    out_filename = "metadata-cumulative-~{today.date}.txt"
            }
            call utils.s3_copy as s3_cdc_dump_cumulative {
                input:
                    infiles         = [cumulative_meta_tsv.out],
                    s3_uri_prefix   = "~{cdc_s3_uri}/",
                    aws_credentials = select_first([cdc_s3_credentials])
            }
        }
        call utils.s3_copy as s3_cdc_dump_meta {
            input:
                infiles         = select_all([cdc_final_metadata, cdc_passing_fasta]),
                s3_uri_prefix   = "~{s3_prefix}/",
                aws_credentials = select_first([cdc_s3_credentials])
        }
        scatter(reads in cdc_aligned_trimmed_bams) {
            call utils.s3_copy as s3_cdc_dump_reads {
                input:
                    infiles         = [reads],
                    s3_uri_prefix   = "~{s3_prefix}/rawfiles/",
                    aws_credentials = select_first([cdc_s3_credentials])
            }
        }
        call utils.s3_copy as s3_cdc_complete {
            input:
                infiles         = [upload_complete.out],
                s3_uri_prefix   = "~{s3_prefix}/",
                aws_credentials = select_first([cdc_s3_credentials]),
                nop_block       = write_lines(flatten([flatten(s3_cdc_dump_reads.out_uris), s3_cdc_dump_meta.out_uris]))
                # this step must wait until all of the scattered reads are finished uploading
        }
    }

    output {
        Array[File]    genbank_response   = select_first([genbank_upload.reports_xmls, []])
        File?          sra_xml            = sra_tsv_to_xml.submission_xml
        Array[File]    sra_response       = select_first([sra_upload.reports_xmls, []])
    }
}
