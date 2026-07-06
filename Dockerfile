FROM alpine:3.21

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY Nodeye-agent-${TARGETOS}-${TARGETARCH} /app/Nodeye-agent
RUN chmod +x /app/Nodeye-agent && touch /.Nodeye-agent-container

ENTRYPOINT ["/app/Nodeye-agent"]
CMD ["--help"]
