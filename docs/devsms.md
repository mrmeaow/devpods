# 📮 devsms Guide

DevPods provides a dedicated `dev-sms-pod` that runs:

- **devsms API** on [http://localhost:4000](http://localhost:4000)
- **devsms UI** on [http://localhost:5153](http://localhost:5153)

## Start only this pod

```bash
bash devpods.sh up sms
```

## Useful checks

```bash
# Tail devsms logs
podman logs -f dev-sms-pod-devsms

```
