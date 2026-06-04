FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends imapfilter spamc ca-certificates lua-socket && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY entrypoint.sh .
COPY main.lua .

RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]