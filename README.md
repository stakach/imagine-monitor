# Imagine Monitor

This is the primary detection service for imagine.

```mermaid
graph TD;
    H264 Broadcast-->Imagine Monitor;
    Imagine Monitor-->Video Stream;
    Imagine Monitor-->Detections;
    Nginx Webserver-->Imagine Monitor
```

### Deploying

You can build an image using `docker build .`
