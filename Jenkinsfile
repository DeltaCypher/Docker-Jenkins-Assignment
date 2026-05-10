// ═══════════════════════════════════════════════════════════
//  Jenkinsfile  –  Docker Deployment Pipeline
//
//  What this pipeline does, step by step:
//  1. Checks out latest code from Git
//  2. Validates the docker-compose file
//  3. Pulls the latest Docker images (so we always use fresh ones)
//  4. Stops any currently running containers (gracefully)
//  5. Builds and starts all containers
//  6. Runs a quick health check to confirm services are up
//  7. On failure → sends a notification (email placeholder)
// ═══════════════════════════════════════════════════════════

pipeline {

    // Run on any available Jenkins agent
    agent any

    // ── Configurable variables ──────────────────────────────────
    environment {
        COMPOSE_FILE    = 'docker-compose.yml'       // path to compose file
        APP_NAME        = 'myapp'                    // used as compose project name
        GIT_REPO        = 'https://github.com/your-org/your-repo.git'  // ← change this
        GIT_BRANCH      = 'main'                     // branch to deploy
        DEPLOY_DIR      = '/opt/myapp'               // directory on Jenkins server
    }

    // ── Triggers ────────────────────────────────────────────────
    triggers {
        // Automatically run pipeline every time code is pushed
        githubPush()
        // OR run on a schedule (e.g., every night at 2 AM):
        // cron('0 2 * * *')
    }

    // ── Pipeline Stages ─────────────────────────────────────────
    stages {

        // ── STAGE 1: Pull latest code from Git ──────────────────
        stage('Checkout Code') {
            steps {
                echo '📥 Pulling latest code from Git...'
                git branch: "${GIT_BRANCH}",
                    url: "${GIT_REPO}"
                // If your repo is private, use credentials:
                // git branch: "${GIT_BRANCH}",
                //     credentialsId: 'github-credentials',
                //     url: "${GIT_REPO}"
            }
        }

        // ── STAGE 2: Validate docker-compose.yml ────────────────
        stage('Validate Docker Compose') {
            steps {
                echo '🔍 Validating docker-compose.yml syntax...'
                sh '''
                    docker compose -f ${COMPOSE_FILE} config
                    echo "✅ docker-compose.yml is valid"
                '''
            }
        }

        // ── STAGE 3: Pull latest Docker images ──────────────────
        stage('Pull Docker Images') {
            steps {
                echo '🐳 Pulling latest images from Docker Hub...'
                sh '''
                    docker compose -f ${COMPOSE_FILE} pull
                    echo "✅ All images pulled successfully"
                '''
            }
        }

        // ── STAGE 4: Stop existing containers ───────────────────
        stage('Stop Old Containers') {
            steps {
                echo '🛑 Stopping any running containers...'
                sh '''
                    # --remove-orphans cleans up containers not in compose file
                    docker compose -p ${APP_NAME} -f ${COMPOSE_FILE} down --remove-orphans || true
                    echo "✅ Old containers stopped"
                '''
            }
        }

        // ── STAGE 5: Build images & start containers ────────────
        stage('Deploy Containers') {
            steps {
                echo '🚀 Building and starting all containers...'
                sh '''
                    # --build  : rebuilds images if Dockerfile changed
                    # -d       : detached mode (runs in background)
                    docker compose -p ${APP_NAME} -f ${COMPOSE_FILE} up --build -d
                    echo "✅ All containers started"
                '''
            }
        }

        // ── STAGE 6: Health Check ────────────────────────────────
        stage('Health Check') {
            steps {
                echo '🏥 Waiting for services to become healthy...'
                sh '''
                    # Give containers 20 seconds to fully start
                    sleep 20

                    echo "--- Running Containers ---"
                    docker compose -p ${APP_NAME} -f ${COMPOSE_FILE} ps

                    # Check nginx is responding on port 80
                    if curl -I http://localhost:80 > /dev/null; then
                        echo "✅ Nginx is UP on port 80"
                    else
                        echo "❌ Nginx health check FAILED"
                        exit 1
                    fi

                    # Check phpMyAdmin is responding on port 8081
                    if curl -I http://localhost:8081 > /dev/null; then
                        echo "✅ phpMyAdmin is UP on port 8081"
                    else
                        echo "❌ phpMyAdmin health check FAILED"
                        exit 1
                    fi
                '''
            }
        }
	
	// ── STAGE 8: Extract Unique IPs ──────────────────────────
        stage('Extract IP Addresses') {
            steps {
                echo '🔍 Extracting IPs from Nginx logs...'
                sh '''
                    # Generate test traffic
                    for i in 1 2 3 4 5; do curl -s http://localhost:80 > /dev/null; done
                    sleep 3
 
                    # Copy log out of container
                    docker cp nginx_server:/var/log/nginx/access.log /tmp/nginx_access.log
 
                    if [ -s /tmp/nginx_access.log ]; then
                        bash scripts/extract_ips.sh /tmp/nginx_access.log
                        mkdir -p reports
                        mv unique_ips_*.txt reports/ 2>/dev/null || true
                        echo "✅ IP report saved"
                    else
                        echo "⚠️ Log empty — skipping"
                    fi
                '''
            }
        }
	/*
	// ── STAGE 9: MySQL Backup to S3 ──────────────────────────
        //
        //  Credentials are injected by Jenkins at runtime using
        //  withCredentials block. They are:
        //    • never written to disk
        //    • masked as **** in all console logs
        //    • not visible in the Jenkinsfile at all
        // ─────────────────────────────────────────────────────────
        stage('MySQL Backup to S3') {
            steps {
                echo '💾 Running MySQL backup...'
 
                // Pull all secrets from Jenkins Credentials Store here
                withCredentials([
                    string(credentialsId: 'db_name',              variable: 'DB_NAME'),
                    string(credentialsId: 'db_password',          variable: 'DB_PASSWORD'),
                    string(credentialsId: 's3_bucket',            variable: 'S3_BUCKET'),
                    string(credentialsId: 'aws_region',           variable: 'AWS_REGION'),
                    string(credentialsId: 'aws_access_key_id',    variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key',variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        # Wait for MySQL to be ready
                        echo "⏳ Waiting for MySQL..."
                        RETRIES=10
                        COUNT=0
                        until docker exec mysql_db mysqladmin ping \
                              -h 127.0.0.1 -u root -p${DB_PASSWORD} --silent 2>/dev/null; do
                            COUNT=$((COUNT+1))
                            [ $COUNT -ge $RETRIES ] && echo "❌ MySQL timeout" && exit 1
                            echo "Retry $COUNT/$RETRIES..."
                            sleep 5
                        done
                        echo "✅ MySQL ready"
 
                        # Export AWS credentials as environment variables
                        # so aws CLI picks them up automatically
                        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
                        export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
 
                        # Run backup script — credentials passed via env vars
                        # No passwords appear in this file or in console logs
                        bash scripts/mysql_backup_s3.sh ${DB_NAME}
                    '''
                }
            }
        } */

        // ── STAGE 10: Show container logs (for debugging) ─────────
        stage('Show Logs') {
            steps {
                echo '📋 Recent container logs...'
                sh '''
                    docker compose -p ${APP_NAME} -f ${COMPOSE_FILE} logs --tail=20
                '''
            }
        }
    }

    // ── Post-pipeline actions ───────────────────────────────────
    post {

        success {
            echo '''
            ╔══════════════════════════════════╗
            ║  ✅ DEPLOYMENT SUCCESSFUL!        ║
            ║                                  ║
            ║  Nginx    → http://localhost      ║
            ║  phpMyAdmin → http://localhost:8081║
            ╚══════════════════════════════════╝
            '''
            // Uncomment to send email on success:
            // mail to: 'team@yourcompany.com',
            //      subject: "✅ Deployment Successful: ${env.JOB_NAME}",
            //      body: "Build #${env.BUILD_NUMBER} deployed successfully."
        }

        failure {
            echo '❌ DEPLOYMENT FAILED! Check logs above.'
            // Roll back: bring up last known containers
            sh '''
                docker compose -p ${APP_NAME} -f ${COMPOSE_FILE} down || true
            '''
            // Uncomment to send email on failure:
            // mail to: 'team@yourcompany.com',
            //      subject: "❌ Deployment FAILED: ${env.JOB_NAME}",
            //      body: "Build #${env.BUILD_NUMBER} failed. Check Jenkins logs."
        }

        always {
            echo '🧹 Cleaning up unused Docker resources...'
            sh 'docker system prune -f || true'
        }
    }
}
