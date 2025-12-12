FROM ghcr.io/tiechui1994/functionless:latest

ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/serverless"]
