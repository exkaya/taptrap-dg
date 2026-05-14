docker run --rm \
  -p 5002:5002 \
  -v "$PWD/certs/server.crt:/etc/nginx/certs/server.crt:ro" \
  -v "$PWD/certs/server.key:/etc/nginx/certs/server.key:ro" \
  tt-site
