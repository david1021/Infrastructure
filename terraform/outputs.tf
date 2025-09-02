output "instance_hostname" {
  description = "Private DNS name of the EC2 instance."
  value       = aws_instance.frontend_server.private_dns
}