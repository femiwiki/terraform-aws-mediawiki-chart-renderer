output "url" {
  description = "The function URL. $wgChartServiceUrl is this URL followed by a token."
  value       = aws_lambda_function_url.this.function_url
}

output "function_name" {
  description = "The name of the function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "The ARN of the function"
  value       = aws_lambda_function.this.arn
}
