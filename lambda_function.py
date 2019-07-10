import boto3
import json
import re

def lambda_handler(event, context):
    if event:
        # SNS: check if the notification is from SNS or not
        try: # SNS
            file_obj = event['Records'][0]['Sns']['Message']
            file_obj = json.loads(file_obj)
            file_obj = file_obj['Records'][0]
        except: # S3
            file_obj = event['Records'][0]
        
        s3 = boto3.client('s3')
        # Get neccesarry info ex) bucket name, file name, region, account # and so on ------------------------
        bucket_name =  file_obj['s3']['bucket']['name']
        file_name = file_obj['s3']['object']['key']
        name = bucket_name.split('-')
        account_id = name[2]
        region = file_obj['awsRegion']
        # ----------------------------------------------------------------------------------------------------
        
        # Get file content -----------------------------------------------------------------------------------
        fileObj = s3.get_object(Bucket=bucket_name, Key=file_name)
        file_content = fileObj['Body'].read().decode('utf-8')
        # ----------------------------------------------------------------------------------------------------
        
        # Remove unnecessary spaces
        pattern = re.compile("^\s+|\s*,\s*|\s+$")
        content_lst = pattern.split(file_content)
        result = []
        
        # Double each numbers
        for x in content_lst:
            # When same line
            if '\n' not in x:
                result.append(re.sub(r'.0$', '', str(float(x)*2)))
            # When newline
            else:
                result.append('\n'.join([re.sub(r'.0$', '', str(float(a)*2)) for a in x.split('\n')]))
        
        # Put result to the new object and the target bucket
        s3.put_object(Body=', '.join(result), Bucket='carvi-output-'+account_id+'-'+region, Key=file_name)

