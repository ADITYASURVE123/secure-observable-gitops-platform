variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "gitops-platform"
}

variable "instance_type" {
  description = "4 vCPU / 16 GB is the practical minimum for Kind + Jenkins + Argo CD + the monitoring stack"
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_gb" {
  description = "Root disk size (container images, Jenkins data, Prometheus data)"
  type        = number
  default     = 80
}

variable "allowed_ssh_cidr" {
  description = "YOUR public IP as /32, e.g. 203.0.113.10/32 (run: curl -s https://checkip.amazonaws.com)"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "Use your own public IP as a /32 (for example 203.0.113.10/32). 0.0.0.0/0 is refused on purpose."
  }
}

variable "ssh_public_key" {
  description = "Contents of your SSH PUBLIC key (cat ~/.ssh/gitops-aws.pub)"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Only used to print ready-to-copy ssh commands in the outputs"
  type        = string
  default     = "~/.ssh/gitops-aws"
}

variable "budget_email" {
  description = "Optional: email for an 80% monthly budget alert. Leave empty to skip."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly budget used by the optional alert"
  type        = number
  default     = 50
}
