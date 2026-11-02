# build
FROM golang:1.22-alpine AS builder
WORKDIR /src

# deps primeiro pra aproveitar o cache
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/evaluation-service .

# runtime
FROM alpine:3.20
# https pro sqs
RUN apk add --no-cache ca-certificates && addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app
COPY --from=builder /out/evaluation-service /app/evaluation-service

USER 10001
ENV PORT=8004
EXPOSE 8004
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1
ENTRYPOINT ["/app/evaluation-service"]
