"""
visitor_counter.py – Atomic visitor counter backed by DynamoDB
Deployed by Terraform in eu-central-1.
"""
import json
import os
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
ITEM_ID = os.environ.get("ITEM_ID", "visitors")

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",  # Locked down in API GW CORS config
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
}


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    try:
        table = dynamodb.Table(TABLE_NAME)

        if method in ("GET", "POST"):
            # Atomic increment – safe under concurrent requests
            response = table.update_item(
                Key={"id": ITEM_ID},
                UpdateExpression="ADD #c :incr",
                ExpressionAttributeNames={"#c": "counter"},
                ExpressionAttributeValues={":incr": 1},
                ReturnValues="UPDATED_NEW",
            )
            count = int(response["Attributes"]["counter"])
            return {
                "statusCode": 200,
                "headers": CORS_HEADERS,
                "body": json.dumps({"visitors": count}),
            }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        print(f"DynamoDB error: {error_code} – {e.response['Error']['Message']}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Could not update counter"}),
        }

    return {
        "statusCode": 405,
        "headers": CORS_HEADERS,
        "body": json.dumps({"error": "Method not allowed"}),
    }
