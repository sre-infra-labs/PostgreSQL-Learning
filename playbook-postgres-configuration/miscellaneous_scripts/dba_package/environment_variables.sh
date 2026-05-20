export PGPWD='xxxxxxxxxxxx'
export PGPWD_OFFICE='xxxxxxxxxxxx'

export ANSIBLE_SSH_PRIVATE_KEY_OFFICE="$(<~/.ssh/id_rsa_office)"
export ANSIBLE_SSH_PRIVATE_KEY_PERSONAL="$(<~/.ssh/id_rsa_personal)"

export SMTP_SERVER_OFFICE="smtp.gmail.com"
export SMTP_PORT_OFFICE="587"
export SMTP_USERNAME_OFFICE="you@gmail.com"
export SMTP_PASSWORD_OFFICE="your_app_password"
export SMTP_EMAIL_TO_OFFICE="recipient@example.com"
export SMTP_EMAIL_FROM_OFFICE="you@gmail.com"

export SMTP_SERVER_PERSONAL="smtp.gmail.com"
export SMTP_PORT_PERSONAL="587"
export SMTP_USERNAME_PERSONAL="sqlagentservice@gmail.com"
export SMTP_PASSWORD_PERSONAL="your_app_password"
export SMTP_EMAIL_TO_PERSONAL="sqlagentservice@gmail.com"
export SMTP_EMAIL_FROM_PERSONAL="sqlagentservice@gmail.com"

export PAGERDUTY_PGDBA_INTEGRATION_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export PAGERDUTY_PGDBA_SERVICE_DIRECTORY_URL=https://ajaydwivedi.pagerduty.com/service-directory/XYZABCDE

export SLACK_DBA_BOT_OAUTH_TOKEN=xoxb-xxxxxxxxxx-xxxxxxxxxx-xxxxxxxxxx

export SLACK_DBA_CHANNEL_ID=C054MFR6CN8
export SLACK_DBA_CHANNEL_NAME="#db-alerts"
export SLACK_DBA_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"

export SLACK_PGDBA_CHANNEL_ID=C094NSNDZJ4
export SLACK_PGDBA_CHANNEL_NAME="#db-postgresql"
export SLACK_PGDBA_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"

export SLACK_PERSONAL_BOT_OAUTH_TOKEN=xoxb-xxxxxxxxxx-xxxxxxxxxx-xxxxxxxxxx
export SLACK_PERSONAL_CHANNEL_ID=C0436G8SCDV
export SLACK_PERSONAL_CHANNEL_NAME="#sqlmonitor"
export SLACK_PERSONAL_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"

# Defaults for automations
export ANSIBLE_SSH_PRIVATE_KEY="$ANSIBLE_SSH_PRIVATE_KEY_PERSONAL"

export SMTP_SERVER="$SMTP_SERVER_OFFICE"
export SMTP_PORT="$SMTP_PORT_OFFICE"
export SMTP_USERNAME="$SMTP_USERNAME_OFFICE"
export SMTP_PASSWORD="$SMTP_PASSWORD_OFFICE"
export EMAIL_TO="$SMTP_EMAIL_TO_OFFICE"
export EMAIL_FROM="$SMTP_EMAIL_FROM_OFFICE"

export SLACK_WEBHOOK_URL="$SLACK_DBA_WEBHOOK_URL"
export SLACK_BOT_TOKEN="$SLACK_DBA_BOT_OAUTH_TOKEN"
export SLACK_CHANNEL_ID="$SLACK_DBA_CHANNEL_ID"
