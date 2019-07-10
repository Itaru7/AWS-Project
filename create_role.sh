#!/bin/bash

# Create role and keep arn of the role
IAM_ROLE_ARN_LAMBDA=`aws iam create-role --role-name "lambda_s3" \
	--assume-role-policy-document '{
		"Version": "2012-10-17",
	   	"Statement": [
	    {
	    	"Effect": "Allow",
	       	"Principal": {
	        	"Service": "lambda.amazonaws.com"
	    	},
	    	"Action": "sts:AssumeRole"
	    }
		]
	}' | jq -r .Role.Arn`


# add S3 policy to the created role
aws iam attach-role-policy \
  --role-name "lambda_s3" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

echo 'pausing script for 10 seconds for IAM to be successfully uploaded.'
sleep 10s

# Upload Lambda function
aws lambda create-function --function-name "lambda_sns" \
     --runtime "python3.6" --role "$IAM_ROLE_ARN_LAMBDA" \
     --handler "lambda_function.lambda_handler" --timeout 3 \
     --memory-size 128 --zip-file "fileb://lambda_function.zip" \
     --region us-east-1
