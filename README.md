# Index
1. [Install nessesary tools](#install-nessesary-tools)
2. [Setup AWS CLI](#setup-aws-cli)
3. [Create Role and upload Lambda function to AWS](#create-role-and-upload-lambda-function-to-aws)
4. [Structure](#structure)
5. [Clean up](#clean-up)

## 1. Install nessesary tools
- **AWS CLI**
	- **Windows**: Download from [here](https://aws.amazon.com/cli/ "here")
	- ** Mac and Linux**
			pip install awscli

- **JQ** - for managing JSON
	- **Windows**
			chocolatey install jq
	- **Mac and Linuux**
			bew install jq
	- **Other options**
	From [here](https://stedolan.github.io/jq/download/ "here")

## 2. Setup AWS CLI
	aws configure
	AWS Access Key ID [****************4GZQ]: <Type your access key>
	AWS Secret Access Key [****************LuYP]: <Type your secret access key>
	Default region name [us-east-2]: us-east-1
	Default output format [None]: <Choose your default output format>

## 3. Create Role and upload Lambda function to AWS
**This role will allow to have full access of S3. 
In this project, we will need this role when uploading output from lambda to output bucket.**

	create_role.sh

**OR**

1. Create Default policy file
		cat > role_lambda.json <<- 'EOF'
		{
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
		}
		EOF

2. Create IAM role on AWS
		# Keep arn of the role
		IAM_ROLE_ARN_LAMBDA=`aws iam create-role \
    		--role-name "lambda_s3" \
    		--assume-role-policy-document file://role_lambda.json | jq -r .Role.Arn`

3. Add S3 policy to the created role
		aws iam attach-role-policy \
			--role-name "lambda_s3" \
			--policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

4. Upload Lambda function to AWS
		aws lambda create-function --function-name "lambda_sns" \
			--runtime "python3.6" --role "$IAM_ROLE_ARN_LAMBDA" \
			--handler "lambda_function.lambda_handler" --timeout 3 \
			--memory-size 128 --zip-file "fileb://lambda_function.zip" \
			--region us-east-1

## 4. Structure
- Upload one lambda, and have SNS to do cross-region (1 to 1 relation with SNS and S3, but only one lambda on the whole system)

![Structure](https://github.com/Itaru7/AWS-Project/blob/master/sns_lambda.png "Structure")

**When creating a new bucket and if it's not in the same region as the lambda function, create SNS into the same region as the newly created bucket and set up to push notification to the lambda function to achieve cross-region structure.
**
Run sns_lambda.sh to automate set up

	bash sns_lambda.sh

**OR**

### Detail
- In this project, the default region is set to **us-east-1**
- Get account number and region from the user
		# Get account number for the bucket
		read -p 'account #: ' account_num
		# Get region for the bucket
		read -p 'region: ' region
- Keep ARN of the lambda function
		LAMBDA_ARN=`aws lambda get-function-configuration \
					--function-name lambda_sns --region us-east-1 | jq -r .FunctionArn`

#### 1. When region is us-east-1

##### 1.1 Add permision to the lambda function to invoke S3 bucket

	aws lambda add-permission --function-name "lambda_sns" \
		--statement-id "s3-put-event-$region" --action "lambda:InvokeFunction"\
		--principal "s3.amazonaws.com" --source-arn "arn:aws:s3:::carvi-input-$account_num-$region" \
		--region us-east-1

##### 1.2 Notification setting for S3

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


#### 2. When the region is not us-east-1
##### 2.1 When SNS is not in the region
2.1.1 Create SNS and keep its ARN

	SNS_ARN=`aws sns create-topic --name s3_sns --region $region | jq -r .TopicArn`

2.1.2 Subscribe lambda

	aws sns subscribe --protocol lambda --topic-arn $SNS_ARN --notification-endpoint $LAMBDA_ARN --region $region

2.1.3  Add permission to the lambda

	aws lambda add-permission --function-name "lambda_sns" \
		--statement-id "sns-put-event-$region" --action "lambda:InvokeFunction" \
		--principal "sns.amazonaws.com" --source-arn $SNS_ARN \
		--region us-east-1

2.1.4 Update SNS Policy to allow the bucket to push notification

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

##### 2.2 When SNS already exists in the region
2.2.1 Get SNS ARN 

	SNS_ARN=`aws sns list-topics --region $region | grep -E ".*:s3_sns\"" | grep -Eo "\"arn.+" | jq -r`

2.2.2 Chcek SNS policy format to how to update to the new policy

		# Add second sourceArn if type is string and convert to array
		if [[ "$(aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region| jq -r .Attributes.Policy | jq '.Statement[0].Condition.ArnLike."aws:SourceArn" | type')" == *"string"* ]]; then

			# Create new policy
			NEW_POLICY=`aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region | jq -r .Attributes.Policy | jq '(.Statement[0].Condition.ArnLike | ."aws:SourceArn" |= .+ " arn:aws:s3:*:*:carvi-input-'$account_num'-'$region'") | ."aws:SourceArn" | split(" ")'`

		# Just add more sourceArn to arry 
		else
			# Create new policy
			NEW_POLICY=`aws sns get-topic-attributes --topic-arn $SNS_ARN --region $region | jq -r .Attributes.Policy | jq '.Statement[0].Condition.ArnLike | ."aws:SourceArn" |= .+["arn:aws:s3:*:*:carvi-input-'$account_num'-'$region'"]' | jq .'"aws:SourceArn"'`
		fi

2.2.3 Update SNS Policy to allow the bucket to push notification 

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

2.2.4 Update to the new policy

	aws sns set-topic-attributes --topic-arn $SNS_ARN --region $region --attribute-name Policy  --attribute-value file://new_policy.json


## 5. Clean up

	bash cleanup.sh

**OR**

	# delete lambda function
	aws lambda delete-function --function-name lambda_sns --region us-east-1
	
	#detach role
	aws iam detach-role-policy --role-name lambda_s3 --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

	#delete role
	aws iam delete-role --role-name lambda_s3

	#delete S3 buckets
	aws s3 ls | grep -E 'carvi-input-.*|carvi-output-.*' | awk '{printf "aws s3 rb s3://%s --force\n",$3}'

