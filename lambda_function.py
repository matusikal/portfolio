import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('TABLE_NAME', 'portfolio-visitor-counter')

ALLOWED_ORIGINS = [
    'https://aleksandermatusik.xyz',
    'https://www.aleksandermatusik.xyz',
]

def lambda_handler(event, context):
    # Check which origin the request is coming from
    origin = event.get('headers', {}).get('origin', '')
    
    allowed_origin = origin if origin in ALLOWED_ORIGINS else ALLOWED_ORIGINS[0]

    table = dynamodb.Table(TABLE_NAME)

    response = table.update_item(
        Key={'id': 'visitor_count'},
        UpdateExpression='ADD visits :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'
    )

    new_count = int(response['Attributes']['visits'])

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': allowed_origin,
        },
        'body': json.dumps({'count': new_count})
    }