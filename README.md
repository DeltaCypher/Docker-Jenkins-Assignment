# 🐳 Docker + Jenkins Assignment – Complete Step-by-Step Guide

---

## 📁 Project Folder Structure

After following this guide, your VM will look like this:

```
/opt/myapp/
├── docker-compose.yml       ← Task 1: All 4 containers defined here
├── Jenkinsfile              ← Task 2: CI/CD pipeline script
├── nginx/
│   └── conf/
│       └── default.conf     ← Nginx virtual host config
└── app/
    └── index.php            ← Sample PHP page

/opt/scripts/
├── extract_ips.sh           ← Task 3: IP extraction script
└── mysql_backup_s3.sh       ← Task 4: MySQL backup + S3 upload
```

---

## ✅ TASK 1 – Docker Setup with docker-compose

### Step 1.1 – Install Docker on your VM

```bash
# Update package list
sudo apt update

# Install prerequisites
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine + Compose plugin
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Let your user run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker                  # apply group change immediately

# Verify installation
docker --version               # e.g. Docker version 24.x
docker compose version         # e.g. Docker Compose version v2.x
```

### Step 1.2 – Create the project directory

```bash
sudo mkdir -p /opt/myapp/nginx/conf
sudo mkdir -p /opt/myapp/app
sudo chown -R $USER:$USER /opt/myapp
cd /opt/myapp
```

### Step 1.3 – Copy your files into place

```bash
# Copy all files you received to /opt/myapp/
cp docker-compose.yml           /opt/myapp/
cp nginx/conf/default.conf      /opt/myapp/nginx/conf/
cp app/index.php                /opt/myapp/app/
```

### Step 1.4 – Start all 4 containers

```bash
cd /opt/myapp
docker compose up -d
```

You will see Docker pulling images and starting containers. First run takes
~2 minutes because it downloads images (nginx:1.25, php:7.3-fpm, mysql:8.0).

### Step 1.5 – Verify containers are running

```bash
docker compose ps
```

Expected output:
```
NAME               IMAGE                   STATUS
nginx_server       nginx:1.25              Up
php_fpm            php:7.3-fpm             Up
mysql_db           mysql:8.0               Up
phpmyadmin_ui      phpmyadmin/phpmyadmin   Up
```

### Step 1.6 – Test in browser

Open a browser and visit:

| Service     | URL                          |
|-------------|------------------------------|
| Nginx + PHP | http://<YOUR-VM-IP>:80       |
| phpMyAdmin  | http://<YOUR-VM-IP>:8081     |

> 💡 Find your VM IP with: `ip addr show | grep inet`

phpMyAdmin login:
- Server: mysql
- Username: root
- Password: rootpassword

### Step 1.7 – Useful Docker commands

```bash
docker compose logs -f nginx      # watch nginx logs live
docker compose logs -f mysql      # watch mysql logs live
docker compose stop               # stop all containers
docker compose down               # stop + remove containers (data is preserved)
docker compose down -v            # stop + remove containers AND volumes (wipes DB!)
```

---

## ✅ TASK 2 – Jenkins Pipeline

### Step 2.1 – Install Jenkins

```bash
# Install Java (Jenkins needs it)
sudo apt install -y openjdk-17-jdk

# Add Jenkins repository
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins

# Start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Allow jenkins user to run docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Step 2.2 – Open Jenkins in browser

Visit: http://<YOUR-VM-IP>:8080

Get the initial admin password:
```bash
sudo cat /var/jenkins_home/secrets/initialAdminPassword
```

Follow setup wizard → Install suggested plugins → Create admin user.

### Step 2.3 – Create a new Pipeline job

1. Click **"New Item"**
2. Enter name: `docker-deploy`
3. Select **"Pipeline"** → Click OK
4. Scroll to **"Pipeline"** section
5. Set **"Definition"** to: `Pipeline script from SCM`
6. Set **"SCM"** to: `Git`
7. Enter your repo URL
8. Set **"Script Path"** to: `Jenkinsfile`
9. Click **Save**

### Step 2.4 – Run the pipeline

1. Click **"Build Now"**
2. Click on the build number → **"Console Output"**
3. Watch the stages execute one by one

### Step 2.5 – Set up GitHub webhook (auto-trigger on push)

In your GitHub repo → Settings → Webhooks → Add webhook:
- Payload URL: `http://<YOUR-VM-IP>:8080/github-webhook/`
- Content type: `application/json`
- Events: Just the push event

---

## ✅ TASK 3 – IP Extraction Script

### Step 3.1 – Install and run the script

```bash
# Copy script to scripts folder
sudo mkdir -p /opt/scripts
cp extract_ips.sh /opt/scripts/
sudo chmod +x /opt/scripts/extract_ips.sh
```

### Step 3.2 – Run against the Docker container's logs

```bash
# Make sure your Docker containers are running first
cd /opt/myapp && docker compose up -d

# Generate some test traffic first
for i in {1..10}; do curl -s http://localhost/ > /dev/null; done

# Now extract IPs from the running nginx container
/opt/scripts/extract_ips.sh --docker
```

### Step 3.3 – Run against a log file on disk

```bash
# Against Nginx log (if running on host, not Docker)
sudo /opt/scripts/extract_ips.sh /var/log/nginx/access.log

# Against a custom log file
/opt/scripts/extract_ips.sh /path/to/any/access.log
```

Sample output:
```
════════════════════════════════════════
  Extracting IPs from: /var/log/nginx/access.log
════════════════════════════════════════

📄 Total log lines : 1523
🌐 Unique IP count  : 47

  REQUESTS   IP ADDRESS
  ─────────  ─────────────────
  342        192.168.1.10
  156        10.0.0.1
  89         172.16.0.5
  ...
```

---

## ✅ TASK 4 – MySQL Backup Script with S3 Upload

### Step 4.1 – Install prerequisites

```bash
# MySQL client tools (for mysqldump)
sudo apt install -y mysql-client

# AWS CLI
sudo apt install -y awscli

# Verify
mysqldump --version
aws --version
```

### Step 4.2 – Configure AWS credentials

```bash
aws configure
```

You will be prompted for:
```
AWS Access Key ID:     ← get from AWS Console → IAM → Your User → Security Credentials
AWS Secret Access Key: ← same place
Default region name:   ap-south-1   (Mumbai)
Default output format: json
```

### Step 4.3 – Create an S3 bucket (if you don't have one)

```bash
aws s3 mb s3://your-bucket-name --region ap-south-1
```

### Step 4.4 – Edit the script with your settings

```bash
cp mysql_backup_s3.sh /opt/scripts/
nano /opt/scripts/mysql_backup_s3.sh
```

Change these lines at the top:
```bash
DB_PASSWORD="rootpassword"          # ← your actual MySQL password
S3_BUCKET="s3://your-bucket-name"   # ← your actual S3 bucket name
AWS_REGION="ap-south-1"             # ← your AWS region
```

### Step 4.5 – Run the backup

```bash
sudo chmod +x /opt/scripts/mysql_backup_s3.sh

# Make sure MySQL container is running
cd /opt/myapp && docker compose up -d

# Run backup for specific database
/opt/scripts/mysql_backup_s3.sh myapp_db

# Run backup for ALL databases
/opt/scripts/mysql_backup_s3.sh --all-databases
```

### Step 4.6 – Verify the S3 upload

```bash
aws s3 ls s3://your-bucket-name/mysql-backups/
```

### Step 4.7 – Schedule daily automatic backups

```bash
# Open your cron jobs
crontab -e

# Add this line (runs at 2:00 AM every day)
0 2 * * * /opt/scripts/mysql_backup_s3.sh myapp_db >> /var/log/mysql_backup.log 2>&1

# Check the log anytime
cat /var/log/mysql_backup.log
```

---

## 🛠️ Troubleshooting

| Problem | Solution |
|---------|----------|
| `Permission denied` on docker | Run `newgrp docker` or log out and back in |
| MySQL container not starting | Check `docker compose logs mysql` for errors |
| phpMyAdmin can't connect | Ensure MySQL is healthy: `docker compose ps` |
| S3 upload fails | Run `aws sts get-caller-identity` to verify credentials |
| Nginx shows 502 Bad Gateway | php-fpm might not be running: `docker compose restart php-fpm` |

---

## 🔑 Quick Reference – All Commands

```bash
# Start everything
cd /opt/myapp && docker compose up -d

# Check status
docker compose ps

# View all logs
docker compose logs -f

# Run IP extraction
/opt/scripts/extract_ips.sh --docker

# Run MySQL backup
/opt/scripts/mysql_backup_s3.sh myapp_db

# Stop everything
docker compose down
```
