import { SQSEvent } from "aws-lambda";

export const handler = async (event: SQSEvent): Promise<void> => {

  console.log("Received event:", JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    try {
      const body =
        typeof record.body === "string" ? JSON.parse(record.body) : record.body;

      const detail = body.detail;

      console.log("📦 Processing order:", detail.orderId);
      await simulateProcessing(1000);
      console.log("✅ Order processed for:", detail.customer);
    } catch (err) {
      console.error("❌ Error processing record:", (err as Error).message);
    }
  }
};

const simulateProcessing = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));
