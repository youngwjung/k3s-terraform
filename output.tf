output "node_ips" {
  value = {
    for idx, node in module.node : "k3s-${idx}" => node.public_ip
  }
}

output "lb_endpoint" {
  value = module.lb.dns_name
}