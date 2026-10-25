# Infraestructura Cloud AWS

Infraestructura AWS completa, 100 % como código con **Terraform**, desplegada con **GitHub Actions sin access keys (OIDC)**.
Para que cada servicio tenga un motivo para estar ahí, todo se monta alrededor de una aplicación de ejemplo:
**ShopFlow**, una tienda online sencilla (catálogo, carrito y pedidos) donde lo importante es la infraestructura.

Proyecto de portfolio basado en el temario de **AWS Solutions Architect Associate (SAA-C03)**. El objetivo del proyecto es aprender de infraestructura en AWS, Despliegue y CI/CD.

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.10-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-eu--west--1-FF9900?logo=amazonaws)

![Arquitectura](docs/img/arquitectura.png)


## Arquitectura

Flujos en Mermaid en [docs/architectureShopFlow.md](docs/architectureShopFlow.md) y detalle de la red en
[docs/network.md](docs/network.md).

| Área | Servicios |
|---|---|
| Red | VPC en 2 AZ con 3 capas de subredes, NAT, VPC endpoints, NACLs, Flow Logs |
| Cómputo | ECS sobre EC2 con capacity provider y Auto Scaling, ALB, ECR, EBS, AWS Backup |
| Datos | RDS PostgreSQL, DynamoDB, ElastiCache (Valkey), S3 |
| Edge y usuarios | Route 53, ACM, CloudFront, WAF, Cognito |
| Serverless | SNS, SQS, Lambda, Step Functions, API Gateway, EventBridge Scheduler |
| Seguridad | KMS, IAM de mínimo privilegio, Secrets Manager, CloudTrail, GuardDuty, IAM Access Analyzer, SSM Session Manager |
| Observabilidad | CloudWatch Logs y Logs Insights, métricas propias (EMF), dashboard, alarmas a SNS, X-Ray |
| Coste | AWS Budgets, Cost Anomaly Detection, etiquetas de coste, Infracost en los PR, recordatorio de apagado |

### Recorrido de una petición

1. El usuario entra en `https://shop.<dominio>`. Route 53 apunta a **CloudFront**, con el **WAF** delante.
2. CloudFront sirve la web desde un **bucket S3 privado** (solo él puede leerlo) y manda `/api/*` al **ALB**.
3. El ALB solo acepta a esa distribución y reparte entre las tareas de la **API (FastAPI)** en **ECS sobre EC2**, en las
   subredes privadas.
4. La API valida el token de **Cognito**, lee el catálogo de **PostgreSQL** (con caché en **Valkey**), guarda el
   carrito en **DynamoDB** y, al hacer el pedido, lo publica en **SNS** y contesta al momento.
5. SNS reparte el pedido a dos colas **SQS**: una arranca el flujo de **Step Functions** (reservar stock → cobrar →
   factura PDF en S3 → confirmar → email) y otra suma las estadísticas del día.
6. Aparte: los carritos caducados avisan por email (DynamoDB Streams), los proveedores actualizan el stock por
   **API Gateway** con API key y cada mañana sale un resumen diario (**EventBridge Scheduler**).

## Estructura del repositorio

```
├── bootstrap/                 # CloudFormation: bucket del state, OIDC de GitHub, roles de CI, budget
├── terraform/
│   ├── modules/
│   │   ├── network/           # VPC, subredes, NAT, endpoints, NACLs, flow logs
│   │   ├── security/          # Claves KMS, CloudTrail, GuardDuty, Access Analyzer
│   │   ├── data/              # RDS, DynamoDB, ElastiCache, S3
│   │   ├── compute/           # ECR, ECS en EC2, ASG, ALB, AWS Backup
│   │   ├── edge/              # Route 53, ACM, CloudFront, WAF, Cognito, logs del edge
│   │   ├── serverless/        # SNS, SQS, Lambda, Step Functions, API Gateway, Scheduler
│   │   ├── observability/     # Dashboard y alarmas
│   │   └── cost/              # Presupuesto del entorno, Cost Anomaly Detection, recordatorio de apagado
│   └── envs/dev/              # Composición de los módulos para el entorno dev
├── app/
│   ├── api/                   # API FastAPI (contenedor ARM)
│   ├── lambdas/               # Ocho Lambdas en Python: pedido, stock, cobro, factura, avisos, partners
│   └── frontend/              # Web estática (HTML, CSS y JavaScript)
├── .github/workflows/         # CI/CD
├── infracost.yml              # Proyecto de Infracost (+ infracost-usage.yml con el uso estimado)
└── docs/                      # Arquitectura, diagrama y red
```

## CI/CD

Workflow [`terraform.yml`](.github/workflows/terraform.yml):

| Cuándo | Qué hace | Rol de AWS |
|---|---|---|
| Pull request / push a `main` | `fmt`, `validate`, `tflint`, `checkov`, `cfn-lint` y `terraform plan` (resultado en el resumen del run) | `github-plan` (solo lectura) |
| Pull request / push a `main` | Infracost: coste estimado del entorno y, en los PR, un comentario con lo que cambia | Ninguno (lee el código) |
| Manual (*Run workflow*) | `plan`, `apply` o `destroy` del entorno `dev`, con aprobación en el environment. El `apply` también construye la imagen de la API, la sube a ECR y la despliega en ECS | `github-apply` |

Las credenciales de AWS son temporales y se obtienen por OIDC: no hay ninguna access key guardada en GitHub.
Los jobs que necesitan AWS se saltan solos mientras no existan las variables del repositorio, así que el CI sale en
verde aunque el entorno no esté configurado.

## Decisiones de arquitectura

Cada decisión con su motivo y lo que se sacrifica a cambio.

### Base del proyecto

- **Bootstrap con CloudFormation, el resto con Terraform.** El bucket del state y los roles de CI tienen que existir
  antes que Terraform (si los creara él, su state dependería de sí mismo). Un único stack crea el bucket, el proveedor
  OIDC, los dos roles y la alerta de presupuesto, que así nunca se borra con un `destroy`.
- **GitHub Actions con OIDC y dos roles.** `plan` es de solo lectura y lo puede usar cualquier PR; `apply` solo lo
  acepta un job del environment `dev`, que pide aprobación manual. Un PR malicioso solo puede leer. El rol de `apply`
  tiene permisos amplios porque toca muchos servicios: se acota por quién puede asumirlo.
- **State en S3 con bloqueo nativo** (`use_lockfile`), sin tabla de DynamoDB: un recurso menos. Bucket versionado,
  cifrado, privado y solo HTTPS.
- **Crear y destruir por sesión.** Encendido 24/7 costaría 100-130 USD/mes; creando el entorno al empezar a trabajar y
  destruyéndolo al acabar, 5-15 USD/mes. Lo caro va detrás de variables y todo lleva las etiquetas `Project` y
  `Environment`.

### Red

- **Instancia NAT en dev, NAT Gateway por variable** (`nat_mode`). Un NAT Gateway cuesta unos 35 USD/mes; una `t4g.nano`
  haciendo NAT, unos 0,01 USD/h. Es un punto único de fallo, aceptable en dev; pasar a NAT Gateway (uno por AZ) es
  cambiar una variable.
- **Gateway endpoints de S3 y DynamoDB** siempre activos: son gratis y quitan ese tráfico del NAT.
- **La capa de datos no tiene ruta a Internet** y su NACL solo admite PostgreSQL (5432) y Valkey (6379) desde la capa
  de aplicación.
- **Sin EFS.** Los ficheros compartidos (imágenes, subidas, facturas) van a S3, y las tareas de ECS no guardan estado.

### Seguridad

- **Dos claves KMS propias** con rotación anual: `logs` (CloudTrail, Flow Logs, CloudWatch Logs) y `data` (RDS,
  DynamoDB, S3, SNS, SQS, secretos). Separarlas permite dar permisos distintos a registros y a datos.
- **CloudTrail multirregión**, **GuardDuty**, **IAM Access Analyzer** y **cifrado de EBS por defecto**.
- **Cada servicio crea su propio rol IAM** junto a él, con permisos solo para lo que usa (un rol por Lambda, roles de
  instancia, ejecución y tarea en ECS).
- **La contraseña de RDS la gestiona RDS** en Secrets Manager y la rota: no aparece en el código, en el state ni en
  GitHub, y ECS la inyecta en la tarea al arrancar.
- **Sin SSH en ningún sitio:** las instancias se administran por SSM Session Manager.

### Datos

- **Cada dato en su almacén:** catálogo y pedidos relacionales en **RDS PostgreSQL 17** (TLS obligatorio, Multi-AZ por
  variable); carritos en **DynamoDB** con TTL de 24 h y Streams; caché del catálogo en **Valkey**; ficheros en **S3**.
- **Security groups encadenados:** RDS y Valkey solo admiten al grupo `data-clients`. Quien lo lleve puede conectarse;
  no se abren rangos de IP.
- **Buckets privados, versionados, cifrados y con ciclo de vida:** las subidas caducan a los 7 días y las facturas pasan
  a Standard-IA a los 30.

### Cómputo

- **ECS sobre EC2 (Graviton) con capacity provider.** Dos niveles de autoscaling: las tareas (1-4) por CPU y por
  peticiones, y las instancias (1-3) para que quepan. ECS vacía una instancia antes de quitarla.
- **Red `awsvpc`:** cada tarea tiene su IP y sus security groups. Las tareas no pueden leer el IMDS de la instancia.
- **La imagen se construye en el `apply`.** ECR nace vacío con cada entorno, así que el workflow construye la imagen para
  ARM, la sube y fuerza un despliegue; el circuit breaker de ECS deshace un despliegue que no arranca.
- **AWS Backup** diario de los discos EBS, con 7 días de retención.

### Edge y usuarios

- **El dominio vive fuera de Terraform.** Se compra una vez y Terraform solo lo busca: si la hosted zone se borrara en
  un `destroy`, cambiarían sus servidores DNS y el dominio dejaría de funcionar.
- **Una sola dirección para todo:** CloudFront manda `/` al bucket de la web y `/api/*` al ALB. El navegador ve un único
  origen, así que no hace falta CORS.
- **HTTPS hasta el ALB** con dos certificados de ACM (el de CloudFront tiene que estar en us-east-1).
- **El ALB solo admite a esta distribución,** en dos capas: el security group solo deja entrar a CloudFront y el listener
  exige una cabecera secreta que solo conoce esta distribución (si no, cualquier CloudFront de otra cuenta se saltaría el WAF).
- **WAF en CloudFront:** reputación de IPs, reglas comunes, entradas maliciosas (Log4j) y límite de peticiones por IP.
- **Cognito** con login por email y flujo *authorization code* + PKCE. La API comprueba ella misma la firma del token, y
  el carrito se guarda con el ID del usuario, así que nadie puede tocar el de otro.

### Serverless

- **La API solo registra el pedido** y contesta `202`; el resto pasa en segundo plano.
- **Fan-out SNS → SQS:** cada consumidor tiene su cola, sus reintentos y su DLQ, y añadir otro no toca la API.
- **Step Functions Standard con compensación:** si el cobro o la factura fallan, se devuelve el stock y el pedido queda
  rechazado con el motivo. Standard guarda el historial de cada ejecución.
- **Idempotencia en cada paso,** porque SQS entrega "al menos una vez": la ejecución se llama como el pedido, el stock
  se reserva en una transacción que marca el pedido y las estadísticas cuentan cada pedido una sola vez.
- **Stock en DynamoDB** con escrituras condicionales atómicas (`stock >= cantidad`): o se reservan todos los productos
  o ninguno.
- **Lambdas fuera de la VPC:** solo usan APIs de AWS, así que dentro de la VPC solo añadirían dependencia del NAT o
  endpoints de pago.
- **API de partners en API Gateway REST**, porque las API keys y los usage plans solo existen ahí. El cuerpo se valida
  antes de llegar a la Lambda.
- **EventBridge Scheduler** para el resumen diario, porque admite zona horaria (08:00 en Madrid también con el cambio de hora).

### Observabilidad

- **Un dashboard por capas:** pedidos, estado de las alarmas, web, API y datos, serverless y últimos errores.
- **15 alarmas al tema SNS de avisos,** cada una con algo que hacer cuando salta: mensajes en las DLQ, errores de las
  Lambdas, API sin tareas sanas o con errores 5xx, CPU y disco de RDS, errores de la API de partners y pagos rechazados.
  Los pagos y el stock rechazados no cuentan como error: son negocio, y Step Functions ya los trata.
- **Métricas de negocio con Embedded Metric Format:** las Lambdas escriben su log en JSON y CloudWatch lo convierte en
  métricas (`OrdersPlaced`, `OrderValue`, `PaymentsAccepted`, `PaymentsDeclined`, `OutOfStock`), sin llamadas ni
  permisos extra.
- **Logs de CloudFront y del WAF en us-east-1,** porque esos servicios solo entregan allí. Del WAF solo se guardan las
  peticiones bloqueadas, sin la cabecera con el token.
- **X-Ray** en Lambdas, Step Functions y API Gateway.

### Coste

- **Tres capas de aviso:**
  - **Antes de aplicar:** Infracost comenta en cada PR cuánto sube o baja el coste, leyendo solo el código.
  - **Mientras el entorno existe:** presupuesto de 10 USD/mes y Cost Anomaly Detection sobre su gasto etiquetado, y un
    email cada noche a las 22:00 si sigue encendido (el aviso más rápido, porque Budgets tarda horas en ver el gasto).
  - **Siempre:** el presupuesto de la cuenta (20 USD/mes) vive en el bootstrap y nunca se destruye.
- **Infracost calcula 730 horas al mes:** sirve para comparar cambios, no como factura.

## Puesta en marcha

1. **Bootstrap** en `eu-west-1` (stack `infra-cloud-aws-bootstrap`):

   ```bash
   aws cloudformation deploy \
     --region eu-west-1 \
     --stack-name infra-cloud-aws-bootstrap \
     --template-file bootstrap/bootstrap.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides BudgetEmail=tu@correo.com
   ```

   Si la cuenta ya tenía el proveedor OIDC de GitHub, añade `CreateOIDCProvider=false`. Los outputs del stack dan el
   bucket del state y los ARN de los dos roles.
2. **Dominio:** comprar uno en Route 53 (la compra crea su hosted zone).
3. **GitHub:** crear las variables `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `DOMAIN_NAME` y
   `NOTIFICATION_EMAIL` (opcional, recibe los avisos), el secreto `INFRACOST_API_KEY` (opcional, gratis en infracost.io)
   y el environment `dev` con *Required reviewers*.
4. **Billing → Cost allocation tags:** activar `Project` y `Environment` (una vez; aparecen tras el primer `apply`).
5. **Encender:** *Actions → terraform → Run workflow → apply*. Al acabar, el resumen del run tiene los enlaces a la
   tienda, la API de partners y el dashboard. Para apagar, lo mismo con `destroy`.

En local (con una sesión de AWS activa, por ejemplo `aws sso login`):

```bash
cd terraform/envs/dev
cp backend.hcl.example backend.hcl   # y pon el nombre del bucket
terraform init -backend-config=backend.hcl
terraform plan -var domain_name=midominio.com
```
