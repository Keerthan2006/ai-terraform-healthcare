output "repository_urls" {
  description = "ECR repository URLs"
  value = {
    for name, repository in aws_ecr_repository.app :
    name => repository.repository_url
  }
}

output "repository_arns" {
  description = "ECR repository ARNs"
  value = {
    for name, repository in aws_ecr_repository.app :
    name => repository.arn
  }
}