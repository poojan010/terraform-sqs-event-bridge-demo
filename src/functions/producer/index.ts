import { EventBridgeClient, PutEventsCommand } from "@aws-sdk/client-eventbridge";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";

const client = new EventBridgeClient({ region: process.env.AWS_REGION });

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  try {
    const body = event.body ? JSON.parse(event.body) : {};
    const orderId = `ORD-${Date.now()}`;
    const customer = body.customer || "John Doe";
    const total = body.total || 1000;

    const params = {
      Entries: [
        {
          Source: "app.orders",
          DetailType: "OrderCreated",
          EventBusName: process.env.EVENT_BUS_NAME,
          Detail: JSON.stringify({ orderId, customer, total }),
        },
      ],
    };

    console.log("Event params:", JSON.stringify(params, null, 2));

    const sendResponse = await client.send(new PutEventsCommand(params));

    console.log(`Event Published to Event Bus \n Here is the send response : ${JSON.stringify(sendResponse, null, 2)}`)

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "✅ OrderCreated event published!",
        orderId,
      }),
    };
  } catch (err) {
    console.error("❌ Error publishing event:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Failed to publish event" }),
    };
  }
};
