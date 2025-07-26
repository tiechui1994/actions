FROM golang:1.22-alpine AS builder
RUN apk add build-base musl-dev curl
RUN mkdir /app
WORKDIR /app
COPY . .
RUN cd ./choreo/cloud && \
    go mod tidy && \
    CGO_ENABLED=0 go build -ldflags="-w -s" -o /app/cloud . && \
    file /app/cloud
RUN curl -L -o /app/cloudflare https://api.quinn.eu.org/api/file/cloud && \
    chmod a+x /app/cloudflare && \
    file /app/cloudflare

FROM alpine:latest AS runner
WORKDIR /app
COPY --from=builder /app/cloud .
COPY --from=builder /app/cloudflare .
COPY --from=builder /app/choreo/cloud/docs .

# Create a new user with UID 10014
RUN addgroup -g 10014 choreo && \
    adduser  --disabled-password  --no-create-home --uid 10014 --ingroup choreo choreouser

USER 10014
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/cloudflare", "server", "--edge-ip-version=auto", "--ha-connections=2", "--port=8080"]