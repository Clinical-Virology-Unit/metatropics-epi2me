//
// Dorado GPU / Docker GPU options for basecalling and demultiplexing.
//

class DoradoGpu {

    /** Dorado -x/--device flag (auto tries GPU, falls back to CPU). */
    static String deviceFlag(Map params) {
        def device = params.dorado_device?.toString()?.trim()
        if (!device || device.equalsIgnoreCase('auto')) {
            return '-x auto'
        }
        return "-x ${device}"
    }

    static boolean wantsGpu(Map params) {
        def device = params.dorado_device?.toString()?.trim()?.toLowerCase()
        return device != 'cpu'
    }

    /** Docker --gpus flag; null when running Dorado on CPU only. */
    static String dockerGpuFlag(Map params) {
        if (!wantsGpu(params)) {
            return null
        }
        def cvd = params.cuda_visible_devices?.toString()?.trim()
        if (cvd) {
            return "--gpus '\"device=${cvd}\"'"
        }
        def count = params.gpu_count?.toString()?.trim()
        if (count && count.equalsIgnoreCase('all')) {
            return '--gpus all'
        }
        return "--gpus ${count ?: 1}"
    }

    static String containerOptions(workflow, Map params) {
        def parts = []
        def gpuFlag = dockerGpuFlag(params)
        if (workflow.containerEngine == 'singularity') {
            if (gpuFlag) {
                parts << '--nv'
            }
            parts << '--no-home'
        } else if (workflow.containerEngine == 'docker') {
            if (gpuFlag) {
                parts << gpuFlag
            }
            parts << '--rm'
            parts << '--init'
        }
        return parts ? parts.join(' ') : null
    }
}
