mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/chart-renderer"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/chart-renderer"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:chart-renderer"
    }
  }
}

variables {
  issuer   = "https://example.com"
  subjects = ["arn:aws:iam::123456789012:role/Wiki", "arn:aws:iam::123456789012:role/OtherWiki"]
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.ISSUER == "https://example.com"
    error_message = "ISSUER is not the issuer."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.AUDIENCES == "chart-renderer"
    error_message = "AUDIENCES is not the default audience."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.SUBJECTS == "arn:aws:iam::123456789012:role/Wiki,arn:aws:iam::123456789012:role/OtherWiki"
    error_message = "SUBJECTS does not list every subject."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.ALGORITHMS == ""
    error_message = "ALGORITHMS is not empty by default."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 2
    error_message = "Concurrency is not capped by default."
  }

  assert {
    condition     = aws_lambda_function_url.this.authorization_type == "NONE"
    error_message = "The function URL is not open for the token check."
  }
}

run "algorithms" {
  command = plan

  variables {
    audiences  = ["chart-renderer", "charts"]
    algorithms = ["ES384", "RS256"]
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.AUDIENCES == "chart-renderer,charts"
    error_message = "AUDIENCES does not list every audience."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables.ALGORITHMS == "ES384,RS256"
    error_message = "ALGORITHMS does not list every algorithm."
  }
}

run "no_subjects" {
  command = plan

  variables {
    subjects = []
  }

  expect_failures = [var.subjects]
}

run "subject_with_comma" {
  command = plan

  variables {
    subjects = ["a,b"]
  }

  expect_failures = [var.subjects]
}

run "http_issuer" {
  command = plan

  variables {
    issuer = "http://example.com"
  }

  expect_failures = [var.issuer]
}

run "no_audiences" {
  command = plan

  variables {
    audiences = []
  }

  expect_failures = [var.audiences]
}
