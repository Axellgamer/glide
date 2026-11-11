# Glide Codespace - nginx template rendered by codespace/boot.sh
# Public port {{PROXY_PORT}} -> Selkies {{SELKIES_PORT}} (with HTTP basic auth
# injected, so the browser inside the Glide UI never sees a login prompt) and
# -> Glide console API {{CONSOLE_PORT}} under /glide/.

worker_processes 1;
pid {{NGINX_HOME}}/nginx.pid;
error_log {{NGINX_HOME}}/logs/error.log warn;

events {
    worker_connections 1024;
}

http {
    default_type application/octet-stream;
    access_log off;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    server_tokens off;

    # nginx runs unprivileged here, so every temp path lives under ~/.glide.
    client_body_temp_path {{NGINX_HOME}}/tmp/client;
    proxy_temp_path {{NGINX_HOME}}/tmp/proxy;
    fastcgi_temp_path {{NGINX_HOME}}/tmp/fastcgi;
    uwsgi_temp_path {{NGINX_HOME}}/tmp/uwsgi;
    scgi_temp_path {{NGINX_HOME}}/tmp/scgi;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen {{PROXY_PORT}};
        server_name _;
        # Selkies file transfers and clipboard uploads can be large.
        client_max_body_size 0;

        # The console API (status, logs, actions) for the Glide UI.
        location /glide/ {
            proxy_pass http://127.0.0.1:{{CONSOLE_PORT}}/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
            proxy_buffering off;
        }

        # The stream itself: Selkies HTML + /api/websockets.
        location / {
            proxy_pass http://127.0.0.1:{{SELKIES_PORT}};
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Authorization "Basic {{AUTH_B64}}";

            # Streaming sessions are long lived and must not be buffered.
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_max_temp_file_size 0;

            # Selkies is framed inside the Glide UI; its own CSP governs that.
            proxy_hide_header X-Frame-Options;
        }
    }
}
