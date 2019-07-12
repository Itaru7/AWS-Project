# delete lambda function
aws lambda delete-function --function-name lambda_sns --region us-east-1

#detach role
aws iam detach-role-policy --role-name lambda_s3 --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

#delete role
aws iam delete-role --role-name lambda_s3

# delete all topics
for x in $(aws s3 ls | grep -E '.*input.*' | cut -d " " -f 3 | cut -d "-" -f 4-6 | uniq -u | xargs -I{} aws sns list-topics --region {} |  awk '{for(i=1;i<=NF;i++){if($i~/.*s3_sns.*/){print $i}}}');  
do 
	region=`echo $x | awk '{split($0, a, ":"); print a[4]}'`
	account_num=`echo $x | awk '{split($0, a, ":"); print a[5]}'`
	aws sns delete-topic --topic-arn "arn:aws:sns:$region:$account_num:s3_sns" --region $region
done

#delete all S3 buckets
aws s3 ls | grep -E '.*input.*|.*output.*' | cut -d " " -f 3 | xargs -I{} aws s3 rb s3://{} --force
