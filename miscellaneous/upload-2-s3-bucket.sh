# install package if required
sudo dnf install -y awscli

export AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxxxxxXX
export AWS_SECRET_ACCESS_KEY=xyxyxyxyxyxyxyxyxyxyxy/xxxxxxxxxxxxxxx

# now test connectivity. Should return all existing backup folders
aws s3 ls s3://mys3bucketname/postgres-sample-databases/

# upload contents of a local folder
aws s3 sync /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs s3://mys3bucketname/postgres-sample-databases/

# Upload a file to S3
aws s3 cp /path/to/local/file.txt s3://my-bucket-name/file.txt

# aws s3 cp s3://my-bucket-name/file.txt /path/to/local/file.txt
aws s3 cp s3://my-bucket-name/file.txt /path/to/local/file.txt



