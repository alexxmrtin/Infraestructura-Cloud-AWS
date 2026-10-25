# Arquitectura

Vista general de la aplicación de ejemplo **ShopFlow** sobre la que se monta la infraestructura.

![Arquitectura](img/arquitectura.png)

Debajo, el mismo flujo en Mermaid.

```mermaid
flowchart LR
    U[Usuario] --> R53[Route 53] --> CF[CloudFront + WAF]
    CF -->|/| S3W[S3 frontend]
    CF -->|/api/*| ALB
    subgraph VPC [VPC · 2 AZ]
        ALB --> ECS[ECS sobre EC2 + ASG<br/>API FastAPI]
        ECS --> RDS[(RDS PostgreSQL)]
        ECS --> EC[(ElastiCache Valkey)]
    end
    ECS --> DDB[(DynamoDB carrito)]
    U --> COG[Cognito]
    ECS -->|pedido nuevo| SNS[SNS orders]
    SNS --> SQS1[SQS orders-workflow] --> L1[Lambda start-order] --> SFN[Step Functions]
    SNS --> SQS2[SQS orders-stats] --> L4[Lambda order-stats] --> ST[(DynamoDB stats)]
    SFN --> STK[(DynamoDB stock)]
    SFN --> S3F[S3 facturas]
    SFN --> SNSM[SNS avisos → email]
    DDB -->|Streams, borrado por TTL| L2[Lambda carritos abandonados] --> SNSM
    P[Partners] --> APIGW[API Gateway<br/>API key + usage plan] --> L3[Lambda partners] --> STK
    SCH[EventBridge Scheduler 08:00] --> L5[Lambda resumen diario] --> SNSM
```

Detalle de la red (subredes, rutas, NAT, NACLs): [network.md](network.md).

### Observabilidad

```mermaid
flowchart LR
    SVC[ALB, ECS, RDS, Lambdas, SQS,<br/>Step Functions, API Gateway] -->|métricas| CW[CloudWatch]
    L[Lambdas order-stats, payment, stock] -->|logs EMF| CW
    CF[CloudFront + WAF] -->|métricas y logs<br/>us-east-1| CW
    CW --> D[Dashboard ShopFlow]
    CW --> A[15 alarmas] --> SNSM[SNS avisos → email]
    CW --> Q[Logs Insights]
```

### Coste

```mermaid
flowchart LR
    TAG[default_tags<br/>Project + Environment] --> B[Budget del entorno<br/>10 USD/mes] --> E[Email]
    TAG --> AD[Cost Anomaly Detection] --> E
    SCH[Scheduler 22:00] --> SNSM[SNS avisos] --> E
    PR[Pull request] --> IC[Infracost] --> C[Comentario con la diferencia de coste]
```

## Flujos

| Flujo | Servicios |
|---|---|
| Web | Route 53, ACM, CloudFront, S3 |
| API principal | ALB, ECS en EC2 con Auto Scaling, EBS, ECR |
| Catálogo | RDS PostgreSQL + ElastiCache (Valkey) |
| Carrito | DynamoDB con TTL y Streams |
| Login | Cognito |
| Pedido | SNS → SQS (fan-out a dos colas) → Lambda → Step Functions → DynamoDB / S3 / SNS |
| Carritos abandonados | DynamoDB Streams (solo borrados por TTL) → Lambda → SNS |
| Resumen diario | EventBridge Scheduler → Lambda → SNS |
| API de partners | API Gateway + Lambda con API keys y throttling |
| Observabilidad | CloudWatch (dashboard, alarmas → SNS, métricas EMF, Logs Insights), logs de CloudFront y WAF en us-east-1, X-Ray |
| Coste | Budgets y Cost Anomaly Detection por etiquetas, recordatorio nocturno de apagado, Infracost en los PR |
