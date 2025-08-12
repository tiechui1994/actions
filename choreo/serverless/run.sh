#!/usr/bin/env sh

curl -sL -o /app/server https://api.quinn.eu.org/api/file/functionless && \
chmod a+x /app/server && \
mv /app/server /app/serverless

/app/serverless