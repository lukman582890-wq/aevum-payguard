FROM python:3.12-slim
WORKDIR /app
COPY web/ /app/web/
EXPOSE 8088
CMD ["python", "-m", "http.server", "8088", "--directory", "/app/web"]
