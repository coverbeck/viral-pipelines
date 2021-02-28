version 1.0

import "../tasks/tasks_terra.wdl" as terra

workflow update_data_tables {
    meta {
        description: "Create data tables in Terra workspace from provided tsv load file."
        author: "Broad Viral Genomics"
        email:  "viral-ngs@broadinstitute.org"
    }

    input {
        String      workspace_name
        String      terra_project
        File        tsv_file
    }

    call terra.upload_entities_tsv as create_table {
        input:
            workspace_name = workspace_name,
            terra_project = terra_project,
            tsv_file = tsv_file
    }

    output {
        String status_message = create_table.status
    }
}