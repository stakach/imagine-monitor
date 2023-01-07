# Imagine Monitor

This is the primary detection service for imagine.

```mermaid
flowchart TD
    B>H264 Broadcast] --> I[[Imagine Service]]
    I --> V[Video Stream Websocket]
    I --> D[Detections Websocket]
    V --> N{{NGINX Webserver}}
    D --> N
    U((Web browser / User)) --> N
```

### Deploying

You can build an image using `docker build .`


#### Multi-arch images

docker buildx build --progress=plain --platform linux/arm64,linux/amd64 -t vontakach/imagine:latest --push .
