#!/bin/bash

# Update system and install dependencies
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y nginx php-fpm php-mysql curl unzip

# Configure PHP-FPM
sudo sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini
sudo systemctl restart php8.1-fpm

# Configure Nginx
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
}
EOF

# Create web application files
sudo cat > /var/www/html/index.php << 'EOF'
<?php
// Web Frontend Application
$project_name = "<?php echo getenv('PROJECT_NAME'); ?>";
$app_alb_dns = "<?php echo getenv('APP_ALB_DNS'); ?>";

echo "<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>$project_name - Web Frontend</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>Welcome to $project_name</h1>
        <p>This is the web frontend server.</p>
        
        <h2>Backend Connection Test</h2>";

// Test connection to backend app ALB
try {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, "http://$app_alb_dns/health");
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($http_code == 200) {
        echo "<div class='status success'>✓ Backend connection successful: $response</div>";
    } else {
        echo "<div class='status error'>✗ Backend connection failed (HTTP $http_code)</div>";
    }
} catch (Exception $e) {
    echo "<div class='status error'>✗ Backend connection error: " . htmlspecialchars($e->getMessage()) . "</div>";
}

echo "
        <h2>Server Information</h2>
        <ul>
            <li><strong>Hostname:</strong> " . gethostname() . "</li>
            <li><strong>PHP Version:</strong> " . phpversion() . "</li>
            <li><strong>Server IP:</strong> " . \$_SERVER['SERVER_ADDR'] . "</li>
            <li><strong>Backend ALB:</strong> $app_alb_dns</li>
        </ul>

        <h2>Test Backend API</h2>
        <form action='/test-backend' method='post'>
            <button type='submit'>Test Backend Connection</button>
        </form>
    </div>
</body>
</html>";
?>
EOF

# Create health check endpoint
sudo cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'healthy',
    'service' => 'web-frontend',
    'timestamp' => date('c'),
    'server' => gethostname()
]);
?>
EOF

# Create test backend endpoint
sudo cat > /var/www/html/test-backend.php << 'EOF'
<?php
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $app_alb_dns = "<?php echo getenv('APP_ALB_DNS'); ?>";
    
    try {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, "http://$app_alb_dns/api/test");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($http_code == 200) {
            $result = json_decode($response, true);
            echo "<div class='status success'>Backend API Response: " . htmlspecialchars($result['message'] ?? $response) . "</div>";
        } else {
            echo "<div class='status error'>Backend API returned HTTP $http_code</div>";
        }
    } catch (Exception $e) {
        echo "<div class='status error'>Backend API error: " . htmlspecialchars($e->getMessage()) . "</div>";
    }
    
    // Redirect back to home after 2 seconds
    header("Refresh:2; url=/");
    exit;
}
?>
EOF

# Set environment variables
echo "PROJECT_NAME=${project_name}" | sudo tee -a /etc/environment
echo "APP_ALB_DNS=${app_alb_dns}" | sudo tee -a /etc/environment

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Enable and start services
sudo systemctl enable nginx
sudo systemctl enable php8.1-fpm
sudo systemctl restart nginx
sudo systemctl restart php8.1-fpm

# Install CloudWatch agent for monitoring (optional)
sudo apt-get install -y amazon-cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-linux

# Create a simple health check script for ALB
sudo cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for ALB
if curl -f http://localhost/health.php > /dev/null 2>&1; then
    exit 0
else
    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/health-check.sh

echo "Web server setup completed successfully!"
echo "Project: ${project_name}"
echo "Backend ALB: ${app_alb_dns}"
sudo systemctl restart nginx
