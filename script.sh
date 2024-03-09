#!/bin/bash

set -x

aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

echo "$aws_account_id"

#Set bucket name
bucket_name="new-upload-bucket-$aws_account_id"

#Set the region
region="ap-south-1"

#Set the lambda role name
lambda_role="SNS-and-S3-AccessRole-for-Lambda"

#Set the lambda function name
function_name="lambda-function-for-s3-event-trigger"

role_response=$(aws iam create-role --role-name $lambda_role  --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
                {
                        "Sid": "Statement1",
                        "Effect": "Allow",
                        "Principal": {
                                "Service": "lambda.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                }
        ]
}')

#Extract the Role ARN from the role response
#role_arn=$()

role_arn=$(echo "$role_response" | jq -r '.Role.Arn')

aws iam attach-role-policy --role-name $lambda_role --policy-arn 'arn:aws:iam::aws:policy/AmazonSNSFullAccess'
aws iam attach-role-policy --role-name $lambda_role --policy-arn 'arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess'

sleep 5

aws lambda create-function --function-name $function_name --runtime python3.12 --zip-file fileb://my-lambda-function.zip --handler lambda-handler --role "arn:aws:iam::$aws_account_id:role/$lambda_role"

aws s3 mb s3://$bucket_name --region $region

# Add Permissions to S3 Bucket to invoke Lambda
aws lambda add-permission \
  --function-name "$function_name" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"

# Create an S3 event trigger for the Lambda function
LambdaFunctionArn="arn:aws:lambda:$region:$aws_account_id:function:$function_name"
aws s3api put-bucket-notification-configuration \
  --region "$region" \
  --bucket "$bucket_name" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$LambdaFunctionArn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# Create an SNS topic and save the topic ARN to a variable
topic_arn=$(aws sns create-topic --name s3-lambda-sns --output json | jq -r '.TopicArn')

# Print the TopicArn
echo "SNS Topic ARN: $topic_arn"

# Trigger SNS Topic using Lambda Function

email_address="shirkandegauri@gmail.com"

# Add SNS publish permission to the Lambda Function
aws sns subscribe \
  --topic-arn "$topic_arn" \
  --protocol email \
  --notification-endpoint "$email_address"

# Publish SNS
aws sns publish \
  --topic-arn "$topic_arn" \
  --subject "A new object created in s3 bucket" \
  --message "Hello people....we have released a new web series on Netflix!"

# aws iam delete-role --role-name $lambda_role

aws s3 rb s3://$bucket_name
