import json
import boto3
import os

# This Lambda function does two things:
# 1. Increments a visitor counter in DynamoDB
# 2. Returns the current count to the browser

dynamodb = boto3.resource('dynamodb')

# The table name comes from an environment variable so it's easy to change
TABLE_NAME = os.environ.get('TABLE_NAME', 'portfolio-visitor-counter')

def lambda_handler(event, context):
    """
    This function is triggered by API Gateway every time
    someone visits the portfolio website.
    """
    table = dynamodb.Table(TABLE_NAME)

    # atomic_counter is the key of our counter item in DynamoDB
    # UpdateExpression: ADD means "add 1 to the visits attribute"
    # If the attribute doesn't exist yet, DynamoDB creates it starting from 0
    response = table.update_item(
        Key={'id': 'visitor_count'},
        UpdateExpression='ADD visits :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'  # returns the new value after update
    )

    new_count = int(response['Attributes']['visits'])

    # CORS headers let the browser (running on your CloudFront domain)
    # talk to the API Gateway (on a different domain)
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',   # CHANGE this to your CloudFront URL in production
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        },
        'body': json.dumps({'count': new_count})
    }
