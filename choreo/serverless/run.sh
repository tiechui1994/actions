#!/usr/bin/env sh

curl -sL https://api.quinn.eu.org/api/file/functionless -o /app/serverless.back && \
chmod a+x /app/serverless.back && \
cp /app/serverless.back /app/serverless

/app/serverless