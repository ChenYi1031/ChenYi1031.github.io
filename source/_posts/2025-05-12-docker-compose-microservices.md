---
title: Docker Compose微服务架构实战：构建可扩展的现代应用
date: 2025-05-12 14:00:00
tags:
  - Docker
  - 微服务
  - Compose
categories:
  - 开发技术
---

# Docker Compose微服务架构实战：构建可扩展的现代应用

在微服务时代，Docker Compose已成为开发、测试和本地部署微服务应用的首选工具。本文将带你从零开始构建一个完整的微服务架构。

## 1. 微服务架构核心组件

```
[客户端] → [API Gateway] → [服务A] → [数据库A]
                     ↘ [服务B] → [数据库B]
                     ↘ [服务C] → [消息队列]
```

## 2. 实战项目：电商微服务系统

### 2.1 项目结构
```
ecommerce/
├── docker-compose.yml
├── services/
│   ├── auth-service/
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   └── requirements.txt
│   ├── product-service/
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   └── requirements.txt
│   └── order-service/
│       ├── Dockerfile
│       ├── app.py
│       └── requirements.txt
└── config/
    └── database.yaml
```

### 2.2 docker-compose.yml 配置文件
```yaml
version: '3.8'

services:
  # 认证服务
  auth-service:
    build: ./services/auth-service
    ports:
      - "8001:8001"
    environment:
      - DATABASE_URL=postgresql://db:5432/auth_db
      - JWT_SECRET=my-secret-key
    depends_on:
      - db
    networks:
      - ecommerce-net
  
  # 商品服务
  product-service:
    build: ./services/product-service
    ports:
      - "8002:8002"
    environment:
      - DATABASE_URL=postgresql://db:5432/product_db
    depends_on:
      - db
    networks:
      - ecommerce-net
  
  # 订单服务
  order-service:
    build: ./services/order-service
    ports:
      - "8003:8003"
    environment:
      - DATABASE_URL=postgresql://db:5432/order_db
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis
    networks:
      - ecommerce-net
  
  # 数据库服务
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: ecommerce
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
    volumes:
      - db_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - ecommerce-net
  
  # Redis缓存
  redis:
    image: redis:7
    ports:
      - "6379:6379"
    networks:
      - ecommerce-net

volumes:
  db_data:

networks:
  ecommerce-net:
    driver: bridge
```

## 3. 服务间通信最佳实践

### 3.1 REST API 调用
```python
# auth-service/app.py
import requests
from flask import Flask, jsonify

app = Flask(__name__)

def call_product_service(product_id):
    try:
        response = requests.get(
            f"http://product-service:8002/api/products/{product_id}",
            timeout=5
        )
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}

@app.route('/api/users/<int:user_id>/orders')
def get_user_orders(user_id):
    # 调用订单服务
    orders = call_order_service(user_id)
    return jsonify({"user_id": user_id, "orders": orders})
```

### 3.2 消息队列通信
```python
# order-service/app.py
import asyncio
import aiormq
import json

async def publish_order_event(order_data):
    connection = await aiormq.connect("amqp://guest:guest@rabbitmq:5672/")
    channel = await connection.channel()
    
    await channel.exchange_declare(
        exchange="order-events",
        exchange_type="topic"
    )
    
    await channel.basic_publish(
        routing_key="order.created",
        body=json.dumps(order_data),
        exchange="order-events"
    )
    
    await connection.close()

async def consume_order_events():
    connection = await aiormq.connect("amqp://guest:guest@rabbitmq:5672/")
    channel = await connection.channel()
    
    await channel.queue_declare(queue="order-processing")
    await channel.queue_bind(
        queue="order-processing",
        exchange="order-events",
        routing_key="order.*"
    )
    
    async def callback(message):
        data = json.loads(message.body)
        print(f"收到订单事件: {data}")
        # 处理订单逻辑
    
    await channel.basic_consume(
        queue="order-processing",
        on_message_callback=callback,
        no_ack=True
    )
```

## 4. 安全与监控配置

### 4.1 网络安全
```yaml
# docker-compose.yml 中的安全配置
services:
  auth-service:
    environment:
      - SECURITY_MODE=production
    secrets:
      - jwt_secret
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8001/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

### 4.2 日志管理
```yaml
services:
  auth-service:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## 5. 生产环境优化

### 5.1 性能调优
```yaml
services:
  db:
    deploy:
      resources:
        limits:
          memory: 2g
          cpus: '1.5'
        reservations:
          memory: 1g
          cpus: '0.5'
```

### 5.2 自动伸缩
```yaml
services:
  product-service:
    deploy:
      replicas: 3
      update_config:
        parallelism: 2
        delay: 10s
        failure_action: rollback
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
```

## 6. 常见问题解决方案

| 问题 | 解决方案 |
|------|----------|
| 服务间无法通信 | 检查网络配置和服务名 |
| 数据持久化丢失 | 使用卷挂载或外部存储 |
| 性能瓶颈 | 添加负载均衡和连接池 |
| 调试困难 | 使用 `docker logs` 和 `docker exec` |

> **经验分享**：Docker Compose适合开发和测试环境，生产环境建议使用Kubernetes。但在本地开发时，Compose是快速搭建微服务架构的最佳选择！

[阅读更多](https://chenyi1031.github.io/2025/05/12/docker-compose-microservices/)