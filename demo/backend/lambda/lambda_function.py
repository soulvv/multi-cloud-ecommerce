import boto3
import json
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get("TABLE_NAME", "mce-dev-products")
table = dynamodb.Table(table_name)

# Helper class to convert Decimal -> int/float
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            # agar number decimal hai aur pura integer hai
            if obj % 1 == 0:
                return int(obj)
            else:
                return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    try:
        response = table.scan()
        items = response.get('Items', [])
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(items, cls=DecimalEncoder)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({"error": str(e)})
        }
