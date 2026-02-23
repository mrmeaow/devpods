# 🪣 MinIO Guide

DevPods provides a dedicated `dev-minio-pod` that runs:

- **MinIO API** on [http://localhost:9000](http://localhost:9000)
- **MinIO Console** on [http://localhost:9001](http://localhost:9001)

## Start only this pod

```bash
bash devpods.sh up minio
```

## Default credentials

From `~/.devpods/.env`:

```bash
MINIO_ROOT_USER=devminio
MINIO_ROOT_PASS=devminio123
MINIO_BUCKET=devsms
```

## Useful checks

```bash
# MinIO liveness endpoint
curl -I http://localhost:9000/minio/health/live

# Tail MinIO logs
podman logs -f dev-minio-pod-minio
```
