variable "vpc_cidr" {
  description = "VPC 대역대"
  type        = string
  default     = "10.100.0.0/24"
}

variable "num_node" {
  description = "노드 갯수"
  type        = number
  default     = 3
}