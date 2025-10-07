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
