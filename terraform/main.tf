resource "aws_sqs_queue" "my_demo_sqs_queue" {
  name = "my-demo-sqs-queue"

  delay_seconds              = 0
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 5
}
