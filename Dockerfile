FROM alpine:3.20

RUN apk add --no-cache bash curl jq ca-certificates tzdata iproute2

WORKDIR /app
COPY update-ddns.sh entrypoint.sh /app/
RUN chmod +x /app/update-ddns.sh /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
