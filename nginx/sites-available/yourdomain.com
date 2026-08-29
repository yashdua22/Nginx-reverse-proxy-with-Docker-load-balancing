upstream backend_pool {
    least_conn;

    server 127.0.0.1:3001 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=3 fail_timeout=30s;

    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name devopsdiaries.in www.devopsdiaries.in;

    access_log /var/log/nginx/yourdomain.access.log detailed;
    error_log  /var/log/nginx/yourdomain.error.log warn;

    location / {
        proxy_pass http://backend_pool;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}