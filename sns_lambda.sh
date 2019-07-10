#!/bin/bash

# Get account number for the bucket
read -p 'account #: ' account_num

# Get region for the bucket
read -p 'region: ' region

# Check if the bucket is already exsits or not
if aws s3 ls | grep -E "carvi-input-$account_num-$region$"; then
	echo 'The bucket with the given account number and region is already exsits.'
else
	# Create input and output bucket ----------------------------------------------------------------------------------------------------------------------------------
	aws s3 mb s3://carvi-input-$account_num-$region --region $region
	aws s3 mb s3://carvi-output-$account_num-$region --region $region
	# -----------------------------------------------------------------------------------------------------------------------------------------------------------------

	# Get the lambda ARN
	LAMBDA_ARN=`aws lambda get-function-configuration \
					--function-name lambda_sns --region us-east-1 | jq -r .FunctionArn`

	# Check if lambda and specified region is in the same region
	if ! aws lambda list-functions --region $region | grep -E "\"lambda_sns\","; then
		
		# Create SNS if doesn't exist in specified region 
		if ! aws sns list-topics --region $region | grep -E ".*:s3_sns\""; then

			# Create SNS and keep its ARN
			SNS_ARN=`aws sns create-topic --name s3_sns --region $region | jq -r .TopicArn`
			
			# Subscribe lambda
			aws sns subscribe --protocol lambda --topic-arn $SNS_ARN --notification-endpoint $LAMBDA_ARN --region $region
			
			# Add permission to the lambda
			aws lambda add-permission --function-name "lambda_sns" \
				--statement-id "sns-put-event-$region" --action "lambda:InvokeFunction" \
				--principal "sns.amazonaws.com" --source-arn $SNS_ARN \
				--region us-east-1

			# Update SNS Policy to allow the bucket to push notification
			aws sns set-topic-attributes --topic-arn $SNS_ARN --attribute-name Policy --region $region \
			  --attribute-value '{
			      "Version": "2008-10-17",
			      "Id": "s3-publish-to-sns",
			      "Statement": [{
			              "Effect": "Allow",
			              "Principal": { "AWS" : "*" },
			              "Action": [ "SNS:Publish" ],
			              "Resource": "'$SNS_ARN'",
			              "Condition": {
			                  "ArnLike": {
			                      "aws:SourceArn": "arn:aws:s3:*:*:'carvi-input-$account_num-$region'"
			                  }
			              }
			      }]
			  }'
		
		# Setup notification setting via SNS
		else
			# Get SNS ARN 
			SNS_ARN=`aws sns list-topics --region $region | grep -E ".*:s3_sns\"" | grep -Eo "\"arn.+" | jq -r`
			
			# Add second sourceArn if type is string and convert to array
			if [[ "$(aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region| \
			 		jq -r .Attributes.Policy | jq '.Statement[0].Condition.ArnLike."aws:SourceArn" | type')" \
			 		== *"string"* ]]; then

			 	# Create new policy
				NEW_POLICY=`aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region | \
					jq -r .Attributes.Policy | jq '(.Statement[0].Condition.ArnLike | ."aws:SourceArn" |= .+ " arn:aws:s3:*:*:carvi-input-'$account_num'-'$region'") | ."aws:SourceArn" | split(" ")'`

			# Just add more sourceArn to arry 
			else
				# Create new policy
				NEW_POLICY=`aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region | \
					jq -r .Attributes.Policy | jq '.Statement[0].Condition.ArnLike | ."aws:SourceArn" |= .+["arn:aws:s3:*:*:carvi-input-'$account_num'-'$region'"]' | jq .'"aws:SourceArn"'`
			fi

			# Update SNS Policy to allow the bucket to push notification ----------------------------------------------------------------------------------------------------------------------------------
			cat > new_policy.json <<- EOF
			{
			    "Version": "2008-10-17",
			    "Id": "s3-publish-to-sns",
			    "Statement": [{
			            "Effect": "Allow",
			            "Principal": { "AWS" : "*" },
			            "Action": [ "SNS:Publish" ],
			            "Resource": "$SNS_ARN",
			            "Condition": {
			                "ArnLike": {
			                    "aws:SourceArn":$NEW_POLICY
			                }
			            }
			    }]
			}
			EOF

			# Update to the new policy
			aws sns set-topic-attributes --topic-arn $SNS_ARN --region $region --attribute-name Policy \
			   --attribute-value file://new_policy.json
			# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
		fi


		# Add a notification to the S3 bucket so that it sends messages to the SNS topic when objects are created (or updated).
		aws s3api put-bucket-notification --region $region --bucket carvi-input-$account_num-$region \
		  --notification-configuration '{
		    "TopicConfiguration": {
		      "Events": [ "s3:ObjectCreated:*" ],
		      "Topic": "'$SNS_ARN'"
		    }
		  }'

	# Setup notification from S3 directly	
	else
		# Add permission to the lambda in order to invoke newly created S3
		aws lambda add-permission --function-name "lambda_sns" \
			--statement-id "s3-put-event-$region" --action "lambda:InvokeFunction"\
			--principal "s3.amazonaws.com" --source-arn "arn:aws:s3:::carvi-input-$account_num-$region" \
			--region us-east-1

		# Notification setting from s3 to lambda
		aws s3api put-bucket-notification-configuration \
			--bucket carvi-input-$account_num-$region \
			--notification-configuration '{
				"LambdaFunctionConfigurations": [
				  {
				    "LambdaFunctionArn": "'$LAMBDA_ARN'",
				    "Events": [ "s3:ObjectCreated:*" ]
				  }
				]
			  }'
	fi
fi 
