output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "ssh_command" {
  description = "Open a shell on the instance"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.this.public_ip}"
}

output "tunnel_command" {
  description = "Run on your LAPTOP and leave open: makes the UIs available at localhost:8080 (apps) and localhost:8081 (Jenkins)"
  value       = "ssh -i ${var.ssh_private_key_path} -N -L 8080:localhost:8080 -L 8081:localhost:8081 ubuntu@${aws_instance.this.public_ip}"
}

output "ssm_command" {
  description = "Alternative to SSH (no open port needed; requires the AWS CLI Session Manager plugin)"
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}

output "stop_command" {
  description = "Stop paying for compute when you are not using it (disk still costs a little)"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.this.id} --region ${var.region}"
}

output "start_command" {
  value = "aws ec2 start-instances --instance-ids ${aws_instance.this.id} --region ${var.region}"
}
