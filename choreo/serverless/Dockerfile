FROM tiechui1994/functionless:latest

# Create a new user with UID 10014
RUN addgroup -g 10014 choreo && \
    adduser  --disabled-password  --no-create-home --uid 10014 --ingroup choreo choreouser && \
    apk add --no-cache curl

USER 10014

ENV PORT=8080
EXPOSE 8080
CMD ["sh", "-c", "curl -sL -o /tmp/serverless https://api.quinn.eu.org/api/file/functionless && chmod a+x /tmp/serverless && mv /tmp/serverless /app/serverless"]
ENTRYPOINT ["/app/serverless"]

