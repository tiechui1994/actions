FROM tiechui1994/functionless:latest

# Create a new user with UID 10014
RUN addgroup -g 10014 choreo && \
    adduser  --disabled-password  --no-create-home --uid 10014 --ingroup choreo choreouser && \
    apk add --no-cache curl && \
    cp /app/serverless /app/serverless.back

USER 10014

COPY run.sh /app

ENV PORT=8080
ENV TESTING=on
ENV ENDPOINT=https://azure.quinn.eu.org

EXPOSE 8080
ENTRYPOINT ["sh", "/app/run.sh"]

