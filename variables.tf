variable "name" {
  description = "The name of the function, its role and its log group"
  type        = string
  default     = "chart-renderer"
}

variable "issuer" {
  description = "The OpenID Connect issuer of the tokens the function accepts, such as the issuer_identifier of aws_iam_outbound_web_identity_federation. Its JWKS is found through its /.well-known/openid-configuration."
  type        = string

  validation {
    condition     = startswith(var.issuer, "https://") && !endswith(var.issuer, "/")
    error_message = "issuer must be an https URL without a trailing slash."
  }
}

variable "audiences" {
  description = "The audiences a token may have"
  type        = list(string)
  default     = ["chart-renderer"]

  validation {
    condition     = length(var.audiences) > 0 && alltrue([for a in var.audiences : a != "" && !strcontains(a, ",")])
    error_message = "audiences must list at least one audience, none of them empty or with a comma."
  }
}

variable "subjects" {
  description = "The subjects a token may have, such as the ARN of the role of the wiki's instances"
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for s in var.subjects : s != "" && !strcontains(s, ",")])
    error_message = "subjects must list at least one subject, none of them empty or with a comma."
  }
}

variable "algorithms" {
  description = "The signing algorithms a token may use, such as [\"ES384\"]. Empty accepts any algorithm of the issuer's keys."
  type        = list(string)
  default     = []
}

variable "memory_size" {
  description = "Memory for the function in MB. A render peaks near 113 MB."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Seconds a render may take"
  type        = number
  default     = 10
}

variable "reserved_concurrent_executions" {
  description = "How many renders may run at once. The URL is open to anyone, so this bounds what a flood of requests can cost."
  type        = number
  default     = 2
}

variable "log_retention_in_days" {
  description = "How long the function's logs are kept"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags for every resource the module creates"
  type        = map(string)
  default     = {}
}
