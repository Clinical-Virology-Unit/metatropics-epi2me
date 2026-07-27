//
// Dorado -x auto uses GPU when the container exposes one; otherwise CPU.
// Docker must pass --gpus for CUDA to be visible; if that fails, retry without GPU.
//

class DoradoGpu {

    static boolean gpuAttempt(task) {
        task.attempt <= 1
    }

    static String containerOptions(workflow, task) {
        def parts = []
        def useGpu = gpuAttempt(task)
        if (workflow.containerEngine == 'singularity') {
            if (useGpu) {
                parts << '--nv'
            }
            parts << '--no-home'
        } else if (workflow.containerEngine == 'docker') {
            if (useGpu) {
                parts << '--gpus 1'
            }
            parts << '--rm'
            parts << '--init'
        }
        return parts ? parts.join(' ') : null
    }
}
