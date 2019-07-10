# delete lambda function
aws lambda delete-function --function-name lambda_sns --region us-east-1
#detach role
aws iam detach-role-policy --role-name lambda_s3 --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
#delete role
aws iam delete-role --role-name lambda_s3
#delete S3 buckets
aws s3 ls | grep -E '.*input.*|.*output.*' | cut -d " " -f 3 | xargs -I{} aws s3 rb s3://{} --force
