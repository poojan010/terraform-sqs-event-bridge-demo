resource "aws_sqs_queue" "order_processing_queue" {
  name = "order-processing-queue"

  delay_seconds              = 0
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 5
}

resource "aws_cloudwatch_event_bus" "order_bus" {
  name = "order-bus"
}

resource "aws_cloudwatch_event_rule" "order_created_rule" {
  name           = "order-created-rule"
  description    = "Rule to capture OrderCreated events from app.orders source"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name

  event_pattern = jsonencode({
    "source"      = ["app.orders"],
    "detail-type" = ["OrderCreated"]
  })
}

resource "aws_cloudwatch_event_target" "order_created_target" {
  rule           = aws_cloudwatch_event_rule.order_created_rule.name
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  arn            = aws_sqs_queue.order_processing_queue.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-order-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" },
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "eventbridge_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}

resource "aws_iam_role_policy_attachment" "sqs_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_lambda_function" "producer" {
  function_name    = "order-producer"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = "${path.module}/function_producer.zip"
  source_code_hash = filebase64sha256("${path.module}/function_producer.zip")
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.order_bus.name
      AWS_REGION     = "ap-south-1"
    }
  }
}

resource "aws_lambda_function" "consumer" {
  function_name    = "order-consumer"
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = "${path.module}/function_consumer.zip"
  source_code_hash = filebase64sha256("${path.module}/function_consumer.zip")
  role             = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.order_processing_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

resource "aws_api_gateway_rest_api" "order_api" {
  name        = "order-api"
  description = "API to create orders"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.order_api.id
  parent_id   = aws_api_gateway_rest_api.order_api.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_orders" {
  rest_api_id             = aws_api_gateway_rest_api.order_api.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.producer.invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.order_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "order_api_deploy" {
  depends_on  = [aws_api_gateway_integration.lambda_orders]
  rest_api_id = aws_api_gateway_rest_api.order_api.id
}

resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.order_processing_queue.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action   = "sqs:SendMessage",
        Resource = aws_sqs_queue.order_processing_queue.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.order_created_rule.arn
          }
        }
      }
    ]
  })
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.order_bus.name
}

output "event_rule_arn" {
  value = aws_cloudwatch_event_rule.order_created_rule.arn
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.order_processing_queue.arn
}
