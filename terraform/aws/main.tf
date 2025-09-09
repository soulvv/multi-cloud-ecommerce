provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# -------------------- S3 Bucket (Frontend) --------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "mce-dev-frontend-${random_id.suffix.hex}"

  tags = {
    Name        = "MultiCloudFrontend"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# -------------------- DynamoDB Table (Products) --------------------
resource "aws_dynamodb_table" "products" {
  name           = "mce-dev-products"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "productId"

  attribute {
    name = "productId"
    type = "S"
  }

  tags = {
    Name        = "ProductsTable"
    Environment = "dev"
  }
}

# -------------------- IAM Role for Lambda --------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -------------------- Lambda Function --------------------
resource "aws_lambda_function" "products_api" {
  function_name = "ProductsAPI"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = "${path.module}/lambda_function.zip"

  source_code_hash = filebase64sha256("${path.module}/lambda_function.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.products.name
    }
  }
}

# -------------------- API Gateway --------------------
resource "aws_api_gateway_rest_api" "products_api" {
  name        = "ProductsAPI"
  description = "API Gateway for Products Lambda"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.products_api.id
  parent_id   = aws_api_gateway_rest_api.products_api.root_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_method" "get_products" {
  rest_api_id   = aws_api_gateway_rest_api.products_api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.products_api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.get_products.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.products_api.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.products_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.products_api.execution_arn}/*/*"
}

# -------------------- CORS Fix --------------------
resource "aws_api_gateway_method_response" "get_products_response" {
  rest_api_id = aws_api_gateway_rest_api.products_api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.get_products.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "get_products_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.products_api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.get_products.http_method
  status_code = aws_api_gateway_method_response.get_products_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

# -------------------- Deployment + Stage --------------------
resource "aws_api_gateway_deployment" "products_api_deploy" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.products_api.id
}

resource "aws_api_gateway_stage" "products_api_stage" {
  rest_api_id   = aws_api_gateway_rest_api.products_api.id
  deployment_id = aws_api_gateway_deployment.products_api_deploy.id
  stage_name    = "dev"
}

# -------------------- Outputs --------------------
output "bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "products_table" {
  value = aws_dynamodb_table.products.name
}

output "products_api_url" {
  value = "https://${aws_api_gateway_rest_api.products_api.id}.execute-api.us-east-1.amazonaws.com/dev/products"
}
