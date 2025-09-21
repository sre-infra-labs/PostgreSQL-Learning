#!/usr/bin/env python3
import os
import sys
import boto3
from botocore.exceptions import NoCredentialsError, ClientError

def upload_directory(directory_path, bucket, aws_access_key_id, aws_secret_access_key_secret, prefix="",):
    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key_secret,
    )

    for root, dirs, files in os.walk(directory_path):
        for file in files:
            local_path = os.path.join(root, file)
            # Construct S3 path (prefix + relative path)
            relative_path = os.path.relpath(local_path, directory_path)
            s3_path = os.path.join(prefix, relative_path).replace("\\", "/")

            try:
                print(f"Uploading {local_path} -> s3://{bucket}/{s3_path}")
                s3.upload_file(local_path, bucket, s3_path)
            except (NoCredentialsError, ClientError) as e:
                print(f"Failed to upload {local_path}: {e}")
                sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <directory_path>")
        sys.exit(1)

    directory = sys.argv[1]

    bucket = os.environ.get("PG_BACKREST_REPO1_S3_BUCKET_NAME")
    # prefix = os.environ.get("S3_PREFIX", "")
    aws_access_key_id=os.environ.get("PG_BACKREST_REPO1_S3_KEY")
    aws_secret_access_key_secret=os.environ.get("PG_BACKREST_REPO1_S3_KEY_SECRET")

    if not bucket:
        print("Error: S3_BUCKET environment variable is not set.")
        sys.exit(1)

    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a valid directory.")
        sys.exit(1)

    upload_directory(directory, bucket, aws_access_key_id, aws_secret_access_key_secret, prefix="postgres-sample-databases/")

# python3 ./miscellaneous/upload-2-s3-bucket.py /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs

# python3 -m venv .venv-boto3
# source .venv-boto3/bin/activate
# pip install boto3
