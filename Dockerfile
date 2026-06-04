FROM alpine:3.21

RUN apk add --no-cache imapfilter spamassassin-client ca-certificates lua5.4-socket

WORKDIR /app

COPY entrypoint.sh .
COPY main.lua .

RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]