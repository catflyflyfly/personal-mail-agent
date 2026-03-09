FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends imapfilter spamc ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY entrypoint.sh .
COPY main.lua main.lua

RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
