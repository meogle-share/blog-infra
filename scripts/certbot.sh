#!/bin/bash
set -e

DOMAIN="www.meogle.co.kr"
EMAIL="${CERTBOT_EMAIL:-jmsavemail@gmail.com}"
COMPOSE_FILE="docker-compose.yml -f docker-compose.prod.yml"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

usage() {
    echo "Usage: $0 {init|init-staging|renew}"
    echo ""
    echo "Commands:"
    echo "  init         - 초기 인증서 발급"
    echo "  init-staging - 테스트용 인증서 발급 (rate limit 없음)"
    echo "  renew        - 인증서 갱신 (무중단)"
    exit 1
}

create_dummy_cert() {
    echo "==> Creating dummy certificate for nginx startup..."
    docker compose -f $COMPOSE_FILE run --rm --entrypoint sh certbot -c "\
        mkdir -p $CERT_PATH && \
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout $CERT_PATH/privkey.pem \
            -out $CERT_PATH/fullchain.pem \
            -subj '/CN=$DOMAIN'"
}

init() {
    local staging_flag=""
    if [ "${1:-}" = "staging" ]; then
        staging_flag="--staging"
        echo "==> [STAGING] 테스트 모드로 실행합니다."
    fi

    # 기존 nginx 컨테이너 정리
    echo "==> Removing existing nginx container..."
    docker compose -f $COMPOSE_FILE rm -sf web 2>/dev/null || true

    # 더미 인증서 생성 (nginx 시작용)
    create_dummy_cert

    # nginx 시작
    echo "==> Starting nginx with dummy certificate..."
    docker compose -f $COMPOSE_FILE up -d web
    sleep 3

    # webroot 방식으로 실제 인증서 발급 (nginx 중지 불필요)
    echo "==> Requesting certificate for $DOMAIN..."
    docker compose -f $COMPOSE_FILE run --rm certbot certonly \
        --webroot \
        -w /var/www/certbot \
        --agree-tos \
        --no-eff-email \
        --email "$EMAIL" \
        --force-renewal \
        $staging_flag \
        -d "$DOMAIN"

    # nginx reload로 실제 인증서 적용
    echo "==> Reloading nginx with real certificate..."
    docker exec meogle.nginx nginx -s reload

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