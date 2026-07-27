process DORADO_ONT {
    tag "Basecalling"
    label 'process_gpu'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://nanoporetech/dorado:latest' :
        'nanoporetech/dorado:latest' }"

    containerOptions {
        DoradoGpu.containerOptions(workflow, params)
    }

    input:
    path input_dir

    output:
    path "calls.bam", emit: basecalling_ch
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def deviceFlag = DoradoGpu.deviceFlag(params)

    """
    # Run dorado basecaller 
    dorado basecaller ${params.model} $input_dir \
        --no-trim \
        --batchsize 1024 \
        --chunksize 10000 \
        --overlap 500 \
        ${deviceFlag} > calls.bam

    # Get version
    VERSION=\$(dorado --version 2>&1 | tail -n 1)

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$VERSION
    END_VERSIONS
    """
}

