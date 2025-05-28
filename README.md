#  Carbon-Aware Nextflow Pipeline on Kubernetes
This project runs a carbon-aware Nextflow pipeline on any Kubernetes cluster using real-time carbon intensity data from ElectricityMap. The pipeline delays compute-heavy tasks until carbon emissions are low — making your workflows more sustainable.

---

##  What’s Inside?
* **Live carbon-intensity gating** – the `highenergy_std_task` automatically delays execution when CO₂ > 250 g/kWh (configurable) and retries every hour for up to 24 h. Once it starts, it runs to completion.
* **Works on any Kubernetes cluster** – nothing vendor-specific, you only need:
  * `kubectl` access
  * A ReadWriteMany (RWX) storage class (e.g. NFS, CephFS)
  * Outbound internet to query the [ElectricityMap](https://electricitymap.org/) API
* **Self-contained bootstrap scripts** – spin up a PVC, an “uploader” pod, and the Nextflow job with one command.
* **Clean teardown** – `reset.sh` removes every Job/Pod and wipes the shared volume.

---

## 📑 Table of Contents
1. [Prerequisites](#-prerequisites)
2. [Quick-Start (any cluster)](#-quick-start-any-cluster)
3. [Optional: FONDA (HU Berlin) Setup](#-optional-fonda-cluster-setup)
4. [Carbon-Aware Logic](#-carbon-aware-logic)
5. [Debugging & Monitoring](#-debugging--monitoring)
6. [Repository Layout](#-repository-layout)
7. [Output Artifacts](#-output-artifacts)
8. [Clean-Up](#-clean-up)
9. [Customising the Workflow](#-customising-the-workflow)

---

## ✅ Prerequisites
| Requirement | Notes |
|-------------|-------|
| **Kubernetes cluster** | Must expose an RWX StorageClass |
| **CLI tools** | `kubectl`, `envsubst`, `bash` |
| **ElectricityMap API token** | Get one free at <https://electricitymap.org/map> |
| **Nextflow** | `bash <(wget -qO- https://get.nextflow.io)` or `module load nextflow` |

Insert your token into **`green_k8s_workflow.nf`**:

```bash
export ELECTRICITYMAP_TOKEN="YOUR_API_TOKEN_HERE"
```
## 🚀 Quick-Start (any cluster)
```bash
# 1 Choose a namespace (create it if needed)
export NAMESPACE=my-namespace
kubectl create namespace $NAMESPACE 2>/dev/null || true

# 2 Bootstrap shared storage + uploader pod
chmod +x bootstrap-nextflow-carbon.sh
./bootstrap-nextflow-carbon.sh

# 3 Wait for the uploader to be ready
kubectl wait pod/pvc-uploader -n $NAMESPACE --for=condition=Ready

# 4 Upload workflow files into the PVC
envsubst < nextflow.config > processed.config
kubectl cp green_k8s_workflow.nf        $NAMESPACE/pvc-uploader:/workspace/
kubectl cp processed.config              $NAMESPACE/pvc-uploader:/workspace/nextflow.config
kubectl cp nextflow-job.yaml             $NAMESPACE/pvc-uploader:/workspace/

# 5 Launch the carbon-aware Nextflow job
export UNIQUE_ID=$(date +%s)
envsubst < nextflow-job.yaml | kubectl apply -n $NAMESPACE -f -

# 6 Follow progress
kubectl get jobs -n $NAMESPACE
kubectl get pods -n $NAMESPACE
kubectl logs -f job/nextflow-run-$UNIQUE_ID -n $NAMESPACE
```
## 🏛️  Optional: FONDA Cluster Setup (HU Berlin)
```bash
# VPN & kubectl context
sudo wg-quick up $(pwd)/wg0.conf     # connects to FONDA VPN
export KUBECONFIG=config.yml         # points kubectl at the cluster
```
```bash
kubectl get nodes -L usedby          # confirm access
```
Then continue with the Quick-Start section above.

##  Carbon-Aware Logic (inside green_k8s_workflow.nf)

```bash
# Query live CO₂ intensity (default zone = DE)
carbon=$(curl -s "https://api.electricitymap.org/v3/carbon-intensity/latest?zone=${ZONE:-DE}" \
          -H "auth-token: $ELECTRICITYMAP_TOKEN" | jq -r '.carbonIntensity')

# Retry while the grid is “too dirty”
retries=0
while [ "$carbon" -gt "${THRESHOLD:=250}" ] && [ "$retries" -lt 24 ]; do
  echo "⚠️  $carbon gCO₂/kWh > $THRESHOLD — waiting 1 h (attempt $((retries+1))/24)"
  sleep 3600
  carbon=$(curl -s "https://api.electricitymap.org/v3/carbon-intensity/latest?zone=${ZONE:-DE}" \
            -H "auth-token: $ELECTRICITYMAP_TOKEN" | jq -r '.carbonIntensity')
  retries=$((retries+1))
done
```
| 🔧 **Behavior**        | 💡 **Default**     | 🛠️ **How to Change**                 |
|------------------------|--------------------|--------------------------------------|
| Carbon threshold       | `250 gCO₂/kWh`     | Set `THRESHOLD` environment variable |
| Max wait time          | `24 h (24 × 1 h)`  | Edit the `while` loop condition      |
| Grid zone              | `DE`               | Set the `ZONE` environment variable  |

- ✅ Only the **`highenergy_std_task`** is carbon-aware — `standard_task` and `longrun_task` start immediately.
- 🔁 You can **copy and paste the logic** into any other process block to make it carbon-aware.

## 🔍 Debugging & Monitoring

A single run creates **five pods**:

| Pod prefix / name                  | Purpose                                                             |
|------------------------------------|---------------------------------------------------------------------|
| `nextflow-run-<uid>`               | Orchestrates the whole workflow                                     |
| `nf-…` (×3)                        | One pod per pipeline process (`standard_task`, `longrun_task`, `highenergy_std_task`) |
| `pvc-uploader`                     | Keeps the shared PVC mounted for uploads/downloads                  |

```bash
# List all workflow-related pods
kubectl get pods -n $NAMESPACE

# Sample output (fresh run)
NAME                                        READY   STATUS    AGE
nextflow-run-1748339780-9rccl               1/1     Running   32s
nf-0744354e0171577a3a1e1fba2da530a3-4673b   1/1     Running   17s
nf-5e082c2999d7e9efe4d8086f6f8d887b-bd005   1/1     Running   17s
nf-a9c9becd4f599b5bc086b9179294c7f0-23796   1/1     Running   17s
pvc-uploader                                1/1     Running    7m
```
After the workflow finishes, only two pods remain:
```bash
NAME                            READY   STATUS      AGE
nextflow-run-1748339780-9rccl   0/1     Completed   5m
pvc-uploader                    1/1     Running    12m
```
Focus on the carbon-aware task
```bash
# Show only process pods
kubectl get pods -n $NAMESPACE | grep nf-

# Inspect the carbon-aware pod
kubectl exec -it <carbon-aware-pod> -n $NAMESPACE -- ps aux
```
A sleep 3600 entry means highenergy_std_task is pausing until the grid’s carbon intensity drops below the threshold.

## 📁 Repository Layout
```bash
.
├── bootstrap-nextflow-carbon.sh   # Deploy PVC + uploader
├── reset.sh                       # Clean everything
├── green_k8s_workflow.nf          # Nextflow DSL2 pipeline
├── nextflow.config                # K8s executor config + reports
├── nextflow-job.yaml              # Template Job for Nextflow run
├── nextflow-pvc.yaml              # RWX PVC definition
├── pvc-uploader.yaml              # Sleep-infinity pod for file uploads
├── fetch-results.sh               # Convenience downloader
├── .gitignore                     # Ignore work/ etc.
└── README.md
```
## 📤 Output Artifacts

After a successful run the shared PVC (/workspace) contains:
```bash
/workspace/
├── report.html       # Execution summary
├── timeline.html     # Gantt chart of processes
├── trace.txt         # CSV-style trace
└── work/             # Intermediate directories
```
Download them:
```bash
chmod +x fetch-results.sh && ./fetch-results.sh
# or manually:
kubectl cp $NAMESPACE/pvc-uploader:/workspace/report.html   ./report.html
kubectl cp $NAMESPACE/pvc-uploader:/workspace/timeline.html ./timeline.html
kubectl cp $NAMESPACE/pvc-uploader:/workspace/trace.txt     ./trace.txt
```
## 🧼 Clean-Up
```bash
chmod +x reset.sh && ./reset.sh
# Deletes: all Jobs/Pods, uploader pod, ConfigMaps, and PVC content
```
## 🛠️  Customising the Workflow

- Make every task carbon-aware: replicate the retry/sleep logic from **`highenergy_std_task`** in other process definitions.
- Adjust simulated runtimes: in `green_k8s_workflow.nf` change sleep 10, sleep 3600, etc. to match real job durations.
- Tune resource requests: edit labels and nextflow.config to schedule GPU, high-RAM, or node-affinity workloads.
- Happy (low-carbon) computing! 🌍

## 🌍 Why Carbon-Aware Scheduling on Kubernetes?

Electricity’s carbon intensity can swing **5- to 10-fold within a day** as fossil plants ramp up and renewables ebb. By letting Kubernetes decide **when** to launch batch jobs—rather than running them immediately—we can ride those clean-power waves and cut emissions dramatically.

| Key takeaway | Supporting evidence |
|--------------|---------------------|
| **Real-time CO₂ signals are accurate and actionable.** ElectricityMap provides 5-minute carbon intensity data already used for operational decisions. | Tranberg _et al._ [9], Gorka _et al._ [8] |
| **Delaying non-urgent jobs typically cuts emissions by 30–60 %.** | Piontek _et al._ [1]; Beena _et al._ [3] |
| **Carbon checks can be built into workflows, not just schedulers.** | West _et al._ [5], Lechowicz _et al._ [6], James & Schien [2] |

### 🔧 What This Repo Adds

* **Code-integrated carbon gating** – `green_k8s_workflow.nf` *delays* `highenergy_std_task` until live CO₂ ≤ THRESHOLD, then lets the task run to completion without further checks.  
* **Cluster-agnostic design** – no custom controllers, CRDs, or admission webhooks; plain Jobs + PVCs work anywhere.  
* **Minimal footprint** – a 4-line `curl` → `jq` → `sleep` loop; no extra containers or binaries.

🧩 This approach introduces **workflow-level adaptation**, not merely a scheduling adjustment — giving users full control over **which tasks defer** and **under what conditions**.

## 📚 References

### Carbon-aware scheduling & orchestration
[1] T. Piontek *et al.* “Carbon Emission-Aware Job Scheduling for Kubernetes Deployments.” *J. Supercomput.*, 2024. <https://doi.org/10.1007/s11227-023-05506-7>  
[2] A. James and D. Schien. “A Low-Carbon Kubernetes Scheduler.” *ICT4S*, 2019. <https://ceur-ws.org/Vol-2382/ICT4S2019_paper_28.pdf>  
[3] B. M. Beena *et al.* “A Green Cloud-Based Framework for Energy-Efficient Task Scheduling Using Carbon-Intensity Data …” *IEEE Access*, 13, 2025. <https://doi.org/10.1109/ACCESS.2025.3562882>  
[4] W. A. Hanafy *et al.* “Going Green for Less Green: Optimizing the Cost of Reducing Cloud Carbon Emissions.” *ASPLOS ’24*, 2024. <https://doi.org/10.1145/3620666.3651374>  

### Workflow-level & scientific computing
[5] K. West *et al.* “Exploring the Potential of Carbon-Aware Execution for Scientific Workflows.” arXiv:2503.13705, 2025. <https://arxiv.org/abs/2503.13705>  
[6] A. Lechowicz *et al.* “Carbon- and Precedence-Aware Scheduling for Data-Processing Clusters.” arXiv:2502.09717, 2025. <https://arxiv.org/abs/2502.09717>  

### HPC & data-center decarbonization surveys
[7] C. A. Silva *et al.* “A Review on the Decarbonization of High-Performance Computing Centers.” *Renew. Sustain. Energy Rev.* 189 (2024): 114019. <https://doi.org/10.1016/j.rser.2023.114019>  

### Carbon-intensity data & accounting methods
[8] J. Gorka *et al.* “ElectricityEmissions.jl: A Framework for the Comparison of Carbon-Intensity Signals.” arXiv:2411.06560, 2024. <https://arxiv.org/abs/2411.06560>  
[9] B. Tranberg *et al.* “Real-Time Carbon Accounting Method for the European Electricity Markets.” *Energy Strategy Rev.* 26 (2019): 100367. <https://doi.org/10.1016/j.esr.2019.100367>  

