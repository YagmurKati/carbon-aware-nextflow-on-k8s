nextflow.enable.dsl = 2
// Optional: Uncomment GPU or high-memory tasks if needed

workflow {
    highenergy_std_task()
    standard_task()
    longrun_task()

    // Uncomment to enable optional processes:
    // highenergy_memory_task()
    // gpu_task()
}

// Simulated green-aware high-energy task
process highenergy_std_task {
  label 'std_high_en_k8s'
  executor 'k8s'
  container 'ubuntu:22.04'
  errorStrategy 'retry'
  maxRetries 24
  time '2h'

  script:
  """
  export ELECTRICITYMAP_TOKEN="YOUR_API_TOKEN_HERE"  
  apt-get update && apt-get install -y curl jq

  echo "Checking carbon..."
  carbon=\$(curl -s "https://api.electricitymap.org/v3/carbon-intensity/latest?zone=DE" \\
      -H "auth-token: \$ELECTRICITYMAP_TOKEN" | jq -r '.carbonIntensity')

  echo "Current carbon: \$carbon gCO2/kWh"
  if [ "\$carbon" -lt 250 ]; then
    echo "Carbon OK. Running heavy job..."
    sleep 10
  else
    echo "Carbon too high. Waiting an hour before retrying..."
    sleep 3600
    exit 1
  fi
  """
}


// Regular short task
process standard_task {
    label 'standard_k8s'

    script:
    """
    echo 'Running standard task'
    sleep 30
    """
}

// Long-running task
process longrun_task {
    label 'longrun_k8s'

    script:
    """
    echo 'Running longrun task'
    sleep 60
    """
}

// High memory job (optional)
process highenergy_memory_task {
    label 'large_memory_k8s'

    script:
    """
    echo 'Running high memory task'
    sleep 30
    """
}

// GPU job (optional)
process gpu_task {
    label 'gpu_k8s'

    script:
    """
    echo 'Running GPU task'
    sleep 30
    """
}

