#!/bin/bash

# Update system and install dependencies
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y nginx php-fpm php-mysql curl unzip git

# Configure PHP-FPM
sudo sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini
sudo systemctl restart php8.1-fpm

# Configure Nginx for API
sudo cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    # API specific settings
    location /api/ {
        try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

# Create application directory structure
sudo mkdir -p /var/www/html/api

# Create main API endpoint
sudo cat > /var/www/html/index.php << 'EOF'
<?php
header('Content-Type: application/json');

$request_uri = $_SERVER['REQUEST_URI'];
$project_name = "<?php echo getenv('PROJECT_NAME'); ?>";

// Simple routing
if (strpos($request_uri, '/api/test') === 0) {
    // Test endpoint
    echo json_encode([
        'status' => 'success',
        'message' => 'Backend API is working!',
        'service' => 'app-backend',
        'server' => gethostname(),
        'timestamp' => date('c'),
        'project' => $project_name
    ]);
    
} elseif (strpos($request_uri, '/api/db-test') === 0) {
    // Database test endpoint
    testDatabaseConnection();
    
} elseif (strpos($request_uri, '/api/health') === 0) {
    // Health check endpoint
    echo json_encode([
        'status' => 'healthy',
        'service' => 'app-backend',
        'timestamp' => date('c'),
        'server' => gethostname()
    ]);
    
} else {
    // Default endpoint
    echo json_encode([
        'message' => 'Welcome to ' . $project_name . ' Backend API',
        'endpoints' => [
            '/api/test' => 'Test endpoint',
            '/api/db-test' => 'Test database connection',
            '/api/health' => 'Health check',
            '/api/info' => 'Server information'
        ],
        'server' => gethostname()
    ]);
}

function testDatabaseConnection() {
    \$db_host = "<?php echo getenv('DB_HOST'); ?>";
    \$db_username = "<?php echo getenv('DB_USERNAME'); ?>";
    \$db_password = "<?php echo getenv('DB_PASSWORD'); ?>";
    \$db_name = "<?php echo getenv('DB_NAME', true) ?: 'app_db'; ?>";

    try {
        // Attempt database connection
        \$pdo = new PDO(
            "mysql:host=\$db_host;dbname=\$db_name;charset=utf8mb4",
            \$db_username,
            \$db_password,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_TIMEOUT => 5
            ]
        );

        // Test simple query
        \$stmt = \$pdo->query("SELECT 1 as test_value");
        \$result = \$stmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            'status' => 'success',
            'message' => 'Database connection successful!',
            'database' => [
                'host' => \$db_host,
                'name' => \$db_name,
                'connected' => true,
                'test_query' => \$result
            ],
            'server' => gethostname()
        ]);

    } catch (PDOException \$e) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Database connection failed',
            'error' => \$e->getMessage(),
            'database' => [
                'host' => \$db_host,
                'name' => \$db_name,
                'connected' => false
            ],
            'server' => gethostname()
        ]);
    }
}
?>
EOF

# Create health check endpoint
sudo cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');

// Simple health check - just return OK if PHP is working
echo json_encode([
    'status' => 'healthy',
    'service' => 'app-backend',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'checks' => [
        'php' => 'ok',
        'nginx' => 'ok'
    ]
]);
?>
EOF

# Create info endpoint
sudo cat > /var/www/html/info.php << 'EOF'
<?php
header('Content-Type: application/json');

$db_host = getenv('DB_HOST');
$db_username = getenv('DB_USERNAME');
$db_name = getenv('DB_NAME') ?: 'app_db';

echo json_encode([
    'server_info' => [
        'hostname' => gethostname(),
        'php_version' => phpversion(),
        'server_ip' => $_SERVER['SERVER_ADDR'],
        'server_software' => $_SERVER['SERVER_SOFTWARE']
    ],
    'database_info' => [
        'host' => $db_host,
        'database' => $db_name,
        'username' => $db_username,
        'connected' => false
    ],
    'environment' => [
        'project_name' => getenv('PROJECT_NAME'),
        'environment' => getenv('ENVIRONMENT') ?: 'production'
    ],
    'timestamp' => date('c')
]);

// Try to test database connection
if ($db_host && $db_username) {
    try {
        $db_password = getenv('DB_PASSWORD');
        $pdo = new PDO(
            "mysql:host=$db_host;dbname=$db_name;charset=utf8mb4",
            $db_username,
            $db_password,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 3]
        );
        $response['database_info']['connected'] = true;
        $response['database_info']['version'] = $pdo->getAttribute(PDO::ATTR_SERVER_VERSION);
    } catch (PDOException $e) {
        $response['database_info']['error'] = $e->getMessage();
    }
}
?>
EOF

# Set environment variables
echo "PROJECT_NAME=${project_name}" | sudo tee -a /etc/environment
echo "DB_HOST=${db_host}" | sudo tee -a /etc/environment
echo "DB_USERNAME=${db_username}" | sudo tee -a /etc/environment
echo "DB_PASSWORD=${db_password}" | sudo tee -a /etc/environment
echo "DB_NAME=app_db" | sudo tee -a /etc/environment
echo "ENVIRONMENT=${environment}" | sudo tee -a /etc/environment

# Also create environment file for PHP-FPM
sudo cat > /etc/php/8.1/fpm/pool.d/env.conf << EOF
env[PROJECT_NAME] = ${project_name}
env[DB_HOST] = ${db_host}
env[DB_USERNAME] = ${db_username}
env[DB_PASSWORD] = ${db_password}
env[DB_NAME] = app_db
env[ENVIRONMENT] = ${environment}
EOF

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Enable and start services
sudo systemctl enable nginx
sudo systemctl enable php8.1-fpm
sudo systemctl restart nginx
sudo systemctl restart php8.1-fpm

# Install and configure CloudWatch agent for monitoring
sudo apt-get install -y amazon-cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-linux

# Create a health check script for ALB
sudo cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for Application Load Balancer

# Check if Nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "Nginx is not running"
    exit 1
fi

# Check if PHP-FPM is running
if ! systemctl is-active --quiet php8.1-fpm; then
    echo "PHP-FPM is not running"
    exit 1
fi

# Check if application responds
if curl -f http://localhost/health.php > /dev/null 2>&1; then
    exit 0
else
    echo "Application health check failed"
    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/health-check.sh

# Create a simple cron job to monitor the application
sudo cat > /etc/cron.d/app-monitor << EOF
# Monitor application health every minute
* * * * * root /usr/local/bin/health-check.sh > /dev/null 2>&1 || systemctl restart nginx php8.1-fpm
EOF

# Install MySQL client for debugging (optional)
sudo apt-get install -y mysql-client

echo "Application backend setup completed successfully!"
echo "Project: ${project_name}"
echo "Database Host: ${db_host}"
echo "Database User: ${db_username}"
echo "Environment: ${environment}"

# Display initial health check
echo "Performing initial health check..."
curl -s http://localhost/health.php | python3 -m json.tool || echo "Health check failed - please check services"