🚀 Setup AWS S3 for pgBackRest Backups
1️⃣ Create S3 Bucket

Log in to AWS Management Console → Go to S3.

Click Create Bucket:

Bucket name: imajaydwivedi-pg-backups

Region: Closest to DB servers (e.g., ap-south-1 for Mumbai).

Block Public Access: ✅ Keep enabled.

Bucket Versioning: Optional (recommended).

Encryption: ✅ Enable SSE-S3.

Your S3 path will be:

s3://imajaydwivedi-pg-backups/pg-backups/

2️⃣ Create IAM Policy

Go to IAM → Policies → Create Policy and use this JSON:

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::imajaydwivedi-pg-backups"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::imajaydwivedi-pg-backups/*"
        }
    ]
}


Save as: pgbackrest-s3-policy

3️⃣ Create IAM User

IAM → Users → Add user

Username: pgbackrest-user

Access type: Programmatic access

Attach pgbackrest-s3-policy

Save Access Key ID and Secret Access Key

4️⃣ Configure pgBackRest with S3

On each PostgreSQL node, edit pgBackRest config:

RHEL/CentOS: /etc/pgbackrest/pgbackrest.conf

Debian/Ubuntu: /etc/pgbackrest.conf

[global]
repo1-type=s3
repo1-s3-bucket=imajaydwivedi-pg-backups
repo1-s3-endpoint=s3.ap-south-1.amazonaws.com
repo1-s3-region=ap-south-1
repo1-s3-uri-style=path
repo1-path=/pg-backups
repo1-s3-key=<YOUR_AWS_ACCESS_KEY_ID>
repo1-s3-key-secret=<YOUR_AWS_SECRET_ACCESS_KEY>

5️⃣ Test S3 Backup

Run stanza-create first:

pgbackrest --stanza=mydb --log-level-console=info stanza-create


Run a full backup:

pgbackrest --stanza=mydb --type=full backup


Verify in S3:

aws s3 ls s3://imajaydwivedi-pg-backups/pg-backups/

6️⃣ Security Best Practices

Avoid storing keys in pgbackrest.conf. Instead use:

~/.aws/credentials

Or environment variables:

export AWS_ACCESS_KEY_ID=xxxx
export AWS_SECRET_ACCESS_KEY=xxxx


If running on EC2 → use IAM Role (no keys needed).

✅ With this setup, pgBackRest will push backups to:
s3://imajaydwivedi-pg-backups/pg-backups/