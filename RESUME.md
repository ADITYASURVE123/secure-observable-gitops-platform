# Resume-ready summary

Replace the `[__]` values with your own numbers after you run the project (`make drill-summary`, Jenkins build page).
Do not claim numbers you did not measure.

**Secure, Observable GitOps Platform** | Jenkins, Argo CD, Kubernetes (Kind), Trivy, Prometheus, Grafana, Sealed Secrets, k6

- Built a 6-stage Jenkins CI pipeline (JCasC, pinned plugins, isolated Docker-in-Docker) with a Trivy gate that fails the build on fixable
  HIGH/CRITICAL CVEs and archives JSON reports + CycloneDX SBOMs on every run; enforced **0 plaintext secrets** in Git using JCasC env credentials,
  Sealed Secrets and an automated repo scan; hardened workloads (non-root, read-only FS, Pod Security `restricted`, 5 default-deny NetworkPolicies).
- Implemented GitOps delivery with Argo CD (app-of-apps, **6 applications**, auto-sync + self-heal + prune) where Jenkins holds **no cluster
  credentials** and only commits an image tag; releases reach the cluster within the 60s reconcile interval and rollback is a single `git revert`
  (measured release-to-running time: `[__ min]`).
- Delivered full-stack observability with kube-prometheus-stack: RED + **99% < 300ms SLO** dashboards provisioned from Git, 5 alert rules
  (crash-loop, error rate >5%, p95 >300ms, SLO burn-rate) routed to Slack; validated with a chaos drill (error injection, container crashes,
  pod kill, k6 load): detected in **`[__ s]`**, recovered in **`[__ s]`** with no user-facing downtime (2 replicas + PodDisruptionBudget).

**Optional 4th bullet (only if you actually deployed to AWS):**
- Provisioned the platform on AWS `ap-south-1` with Terraform (EC2, IAM/SSM, single-IP security group, IMDSv2, encrypted EBS, budget alert) and/or
  Amazon EKS via eksctl (EBS CSI gp3, VPC CNI network policies, NLB source-range allow-list); tore down with verified zero leftover resources.
