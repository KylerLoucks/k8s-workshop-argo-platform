variable "cluster_names" {
  description = "Names of k3d clusters to create"
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "k3d_binary" {
  description = "Path to k3d binary"
  type        = string
  default     = "k3d"
}

variable "expose_lb" {
  description = "Expose k3d loadbalancer ports on host"
  type        = bool
  default     = false
}

variable "lb_ports" {
  description = "Ports to expose when expose_lb is true"
  type        = list(string)
  default     = [
    "80:80@loadbalancer",
    "443:443@loadbalancer",
  ]
}
