# prober/Dockerfile
FROM python:3.12-slim
RUN pip install --no-cache-dir requests prometheus_client
COPY prober.py /app/prober.py
USER 65534
ENTRYPOINT ["python", "/app/prober.py"]
