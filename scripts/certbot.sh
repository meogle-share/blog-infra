#!/bin/bash
set -e

DOMAIN="www.meogle.co.kr"
EMAIL="${CERTBOT_EMAIL:-jmsavemail@gmail.com}"
COMPOSE_FILE="docker-compose.yml -f docker-compose.prod.yml"

usage() {
    echo "Usage: $0 {init|init-staging|renew}"
    echo ""
    echo "Commands:"
    echo "  init         - 초기 인증서 발급 (nginx 중지 필요)"
    echo "  init-staging - 테스트용 인증서 발급 (rate limit 없음)"
    echo "  renew        - 인증서 갱신 (무중단)"
    exit 1
}

init() {
    local staging_flag=""
    if [ "${1:-}" = "staging" ]; then
        staging_flag="--staging"
        echo "==> [STAGING] 테스트 모드로 실행합니다."
    fi

    echo "==> Stopping nginx for initial certificate..."
    docker compose -f $COMPOSE_FILE stop web

    echo "==> Requesting initial certificate for $DOMAIN..."
    docker compose -f $COMPOSE_FILE run --rm certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        --email "$EMAIL" \
        $staging_flag \
        -d "$DOMAIN"

    echo "==> Starting nginx with SSL..."
    docker compose -f $COMPOSE_FILE up -d web

    echo "==> Done! Certificate issued successfully."
}

renew() {
    echo "==> Renewing certificates..."
    docker compose -f $COMPOSE_FILE run --rm certbot renew \
        --webroot \
        -w /var/www/certbot

    echo "==> Reloading nginx..."
    docker exec meogle.nginx nginx -s reload

    echo "==> Done! Certificates renewed."
}

case "${1:-}" in
    init)
        init
        ;;
    init-staging)
        init staging
        ;;
    renew)
        renew
        ;;
    *)
        usage
        ;;
esac