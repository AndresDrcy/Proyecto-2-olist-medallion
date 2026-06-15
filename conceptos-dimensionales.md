# Conceptos dimensionales del proyecto

Este documento explica los cinco conceptos de modelado dimensional implementados en el proyecto, con énfasis especial en **junk dimension** (la sección más extensa, por solicitud explícita durante la construcción).

---

## 1. Conformed Dimension (Dimensión conformada)

### Definición

Una dimensión es **conformada** cuando es **compartida por múltiples tablas de hechos** con la misma estructura y significado. Esto permite hacer análisis "drill-across": comparar métricas de procesos diferentes usando exactamente los mismos filtros.

### Implementación en este proyecto

- **`dim_customer`** es conformada entre `fact_order_items` y `fact_reviews`. Ambos facts referencian `customer_sk` apuntando a la misma tabla.
- **`dim_date`** es conformada entre `fact_order_items` y `fact_reviews`. Ambos usan `date_sk` apuntando a la misma `dim_date`.

### Por qué importa

Un filtro de slicer en `dim_customer[state] = "SP"` en Power BI aplica **simultáneamente** a ventas y a reviews, sin tener que duplicar lógica. Esto es lo que demuestra el dashboard página 2 (`22-page2.PNG`), donde se mide `Total Sales` y `Average Review Score` por estado con un único slicer.

Sin dimensiones conformadas, tendrías que:
- Mantener dos versiones de `dim_customer` (una para ventas, una para reviews) → trabajo duplicado y riesgo de desincronización
- Hacer filtros distintos para cada visual → modelo confuso para el usuario final

---

## 2. Degenerate Dimension (Dimensión degenerada)

### Definición

Un identificador de transacción que **vive dentro del fact sin tener su propia tabla de dimensión**. No tiene atributos descriptivos propios — solo identifica unívocamente la transacción.

### Implementación en este proyecto

| Columna | En qué fact | Qué identifica |
|---|---|---|
| `order_id` | `fact_order_items` | La orden |
| `order_item_id` | `fact_order_items` | La secuencia del ítem dentro de la orden |
| `review_id` | `fact_reviews` | El review |
| `order_id` | `fact_reviews` | La orden reseñada (también degenerada aquí) |

### Por qué se hace así

Crear `dim_order` con una sola columna (`order_id`) sería absurdo: la tabla no aporta ningún atributo descriptivo que no esté ya en otras dimensiones (cliente, fecha, junk con status, etc.). Los atributos de la orden ya están distribuidos donde corresponden:

- Cliente que compró → `dim_customer`
- Fecha → `dim_date`
- Estado/pago/delivery → `dim_order_junk`
- Producto vendido → `dim_product`
- Vendedor → `dim_seller`

Lo único exclusivo del nivel "orden" es el `order_id` mismo, así que se queda en el fact como **identificador desnudo**. Esto mantiene el modelo limpio sin tablas dimensionales triviales.

### Uso práctico

- Permite **drilling** desde una agregación hacia las transacciones individuales (DISTINCTCOUNT, contar órdenes únicas).
- Es útil para investigación operativa (lookup contra el sistema fuente: "¿qué pasó con la orden X?").
- En DAX: `Total Orders = DISTINCTCOUNT(fact_order_items[order_id])`.

---

## 3. Junk Dimension (Dimensión chatarra)

> Esta sección está **expandida** porque el concepto resultó el más confuso durante la construcción. Si viene de SQL tradicional o de modelos en estrella simples, esta dimensión rompe varios moldes.

### Definición formal (Kimball)

Una **junk dimension** agrupa **múltiples atributos categóricos de baja cardinalidad** que de otra forma serían:

- Banderas/flags sueltas en el fact (inflando su esquema), o
- Mini-dimensiones separadas con 2-8 filas cada una (ruido en el modelo)

La palabra "junk" (basura) es **deliberadamente despectiva**. Viene de Kimball y se refiere a atributos que "no merecen" su propia dimensión por sí mismos. La junk los **agrupa en una sola dimensión** precisamente porque ninguno justifica vivir solo.

### Implementación en este proyecto

**`dim_order_junk`** combina 5 atributos de la orden:

| Atributo | Origen | Cardinalidad |
|---|---|---|
| `order_status` | `silver_orders.order_status` | ~8 valores |
| `delivery_status_bucket` | derivado en Silver | 4 valores |
| `payment_type` | `silver_order_payments.payment_type` | 4 valores |
| `installments_bucket` | derivado en Silver | 4 valores |
| `has_review` | flag derivado | 2 valores |

**Tamaño final: 107 combinaciones** (ver `12-junk-dimension.PNG`).

### El malentendido común

Es fácil confundirse y pensar que una junk dimension es esto:

```
INTERPRETACIÓN INCORRECTA: tres mini-dimensiones separadas

dim_payment_type     dim_installments_bucket    dim_review_flag
┌────────────┐       ┌──────────────────┐       ┌────────────┐
│ credit_card│       │ 1                │       │ true       │
│ boleto     │       │ 2-5              │       │ false      │
│ voucher    │       │ 6-12             │       └────────────┘
│ debit_card │       │ 13+              │
└────────────┘       └──────────────────┘
```

**Eso NO es una junk dimension.** Son tres mini-dimensiones separadas, que es el anti-patrón que la junk vino a resolver.

### Lo que ES una junk dimension

```
UNA SOLA tabla que enumera COMBINACIONES reales

dim_order_junk
┌─────────┬──────────────┬──────────────────┬──────────────┬────────────────┬───────────┐
│ junk_sk │ order_status │ delivery_bucket  │ payment_type │ installments   │ has_review│
├─────────┼──────────────┼──────────────────┼──────────────┼────────────────┼───────────┤
│ 0       │ shipped      │ Not Delivered    │ voucher      │ 1              │ true      │
│ 1       │ delivered    │ On time          │ credit_card  │ 6-12           │ false     │
│ 2       │ delivered    │ On time          │ credit_card  │ 1              │ false     │
│ 3       │ shipped      │ Not Delivered    │ voucher      │ 1              │ false     │
│ ...     │              │                  │              │                │           │
│ 106     │ delivered    │ Late <=7d        │ credit_card  │ 6-12           │ false     │
└─────────┴──────────────┴──────────────────┴──────────────┴────────────────┴───────────┘
```

**Cada fila es una combinación única observada en los datos.** El fact apunta a una única `junk_sk` que resuelve todos los atributos de una vez.

### Anti-patrones que evita la junk dimension

#### Anti-patrón 1: cinco columnas planas en el fact

```sql
fact_order_items(
  order_id, customer_sk, product_sk, ...,
  order_status,            -- ← atributo descriptivo en fact
  delivery_status_bucket,  -- ← atributo descriptivo en fact
  payment_type,            -- ← atributo descriptivo en fact
  installments_bucket,     -- ← atributo descriptivo en fact
  has_review,              -- ← atributo descriptivo en fact
  price, freight_value, ...
)
```

**Problemas:**
- El fact se infla con atributos descriptivos que pertenecen al modelo dimensional, no a las métricas.
- Cualquier cambio en valores válidos requiere actualizar muchísimas filas del fact.
- Conceptualmente confuso: los facts deberían tener "qué medir" (métricas) y "por qué dimensiones medirlo" (FKs).

#### Anti-patrón 2: cinco mini-dimensiones separadas

```
fact_order_items(
  ..., status_sk, delivery_sk, payment_sk, installments_sk, review_sk, ...
)

dim_status (8 filas)
dim_delivery (4 filas)
dim_payment (4 filas)
dim_installments (4 filas)
dim_review (2 filas)
```

**Problemas:**
- 5 FKs adicionales en el fact → 5 joins más en cada query.
- 5 tablas con 2-8 filas cada una → ruido visual y cognitivo en el modelo.
- Mantenimiento: 5 lugares donde gestionar cambios.

#### Patrón Junk (lo que SÍ implementamos)

```
fact_order_items(
  ..., junk_sk, ...   -- ← UNA sola FK
)

dim_order_junk(
  junk_sk, order_status, delivery_status_bucket,
  payment_type, installments_bucket, has_review
)
```

**Ventajas:**
- **Una sola FK** en el fact → un solo join para acceder a los 5 atributos.
- Modelo más limpio visualmente: una dimensión clara con 5 atributos relacionados.
- Mantenimiento centralizado: cambios en valores se gestionan en una sola tabla.

### Por qué 107 combinaciones y no las 1024 teóricas

El producto cartesiano teórico es:

```
8 (order_status) × 4 (delivery) × 4 (payment) × 4 (installments) × 2 (review)
= 1024 combinaciones posibles
```

Pero en la práctica solo **107 combinaciones reales** aparecen en los datos. Las otras 917 no aparecen porque son **imposibles o muy improbables**. Ejemplos:

- `order_status = "canceled"` + `delivery_status_bucket = "On time"` → imposible (una orden cancelada no se entrega).
- `order_status = "delivered"` + `payment_type = "voucher"` + `installments_bucket = "13+"` → ningún voucher en Olist se pagó en 13+ cuotas.

**Decisión técnica:** la junk dimension **solo almacena las combinaciones observadas**, no el producto cartesiano completo. Si almacenaras las 1024:

- Tendrías 917 filas huérfanas (sin referencia desde el fact) → ruido.
- Las queries sobre la dim incluirían combinaciones imposibles → potencial confusión.
- La tabla pesaría 10x más sin aportar información.

### Cuándo NO usar junk dimension

La junk dimension tiene críticos legítimos:

1. **Si los atributos van a crecer en cardinalidad**, la junk crece combinatoriamente y deja de ser "chatarra" — se vuelve una dimensión gorda y poco útil.

2. **Si los atributos son muy usados en queries directas** (e.g., `WHERE payment_type = 'credit_card'` es la consulta más común), una columna directa en el fact puede ser más legible y performante. Algunos equipos modernos en Snowflake/BigQuery prefieren flags planas porque el storage es barato y el join cuesta tiempo.

3. **Si los atributos tienen lógica jerárquica entre sí** (ej. categoría → subcategoría), merecen su propia dimensión con esa jerarquía explícita.

4. **Si solo tienes 1-2 atributos categóricos pequeños**, una junk dimension es overkill. El umbral típico es 3+ atributos.

### Aplicabilidad en este proyecto

Cumplimos los criterios para junk:
- 5 atributos (cumple el "3+" recomendado)
- Cada atributo tiene cardinalidad pequeña (2-8 valores)
- Ninguno tiene jerarquía propia
- Son verdaderamente "garbage": flags y buckets operativos sin riqueza descriptiva
- Es defendible en entrevista como decisión consciente

### Regla mental

> Si un atributo es **pequeño, descriptivo, sin jerarquía propia, y no merece una dimensión solo** — va a la junk.

---

## 4. Slowly Changing Dimension Tipo 2 (SCD Tipo 2)

### Definición

Técnica para **preservar el historial de cambios** en los atributos de una dimensión. Cada vez que cambia un atributo trackeado, se inserta una nueva fila (con surrogate key nueva) y la fila anterior se marca como expirada.

### Implementación en este proyecto

**`dim_customer`** con SCD Tipo 2 sobre `city`, `state` y `zip_prefix`. Olist tiene cambios reales: el mismo `customer_unique_id` aparece con diferentes ubicaciones en distintas órdenes.

### Estructura de la tabla

| Columna | Propósito |
|---|---|
| `customer_sk` | Surrogate key — única por **versión** del cliente |
| `customer_natural_id` | Natural key = `customer_unique_id` — única por **persona** |
| `city`, `state`, `zip_prefix` | Atributos trackeados (SCD2) |
| `attribute_hash` | SHA-256 hash de los atributos trackeados para detección eficiente de cambios |
| `valid_from` | Timestamp de inicio de esta versión |
| `valid_to` | Timestamp de fin de esta versión (`9999-12-31` si es la actual) |
| `is_current` | Booleano para acceso rápido a la versión vigente |

### Construcción en el notebook 03

El algoritmo construye las versiones desde el historial completo de órdenes:

1. **Eventos por cliente:** join entre `silver_customers` y `silver_orders` para obtener cada `customer_unique_id` con cada uno de sus `order_purchase_timestamp`.
2. **Hash de atributos:** `sha2(concat_ws("|", city, state, zip), 256)` para cada evento.
3. **Detectar versiones nuevas:** usar `LAG()` ordenando por `event_timestamp` — una versión nueva inicia cuando el hash difiere del hash de la fila anterior del mismo cliente (o cuando es el primer evento).
4. **Calcular vigencias:** `valid_from` = `event_timestamp` actual; `valid_to` = `LEAD(event_timestamp)` o `9999-12-31` si es la última.

### Por qué importa

Análisis histórico correcto. Si un cliente vivía en SP cuando compró un producto en marzo, y se mudó a RJ en septiembre, una pregunta como "¿cuáles fueron las ventas de SP en marzo?" debe atribuir esa orden a **SP, no a RJ**.

Sin SCD2 (con sobrescritura tipo SCD1), perderías esa historia: todas las órdenes pasadas del cliente quedarían atribuidas a su ubicación actual.

### Lookup SCD2-aware en facts

En el notebook 04, el `customer_sk` se asigna al fact buscando la **versión vigente al momento de la transacción**, no la versión actual:

```python
.join(dim_customer.alias("dc"),
      (col("i.customer_unique_id") == col("dc.customer_natural_id")) &
      (col("i.order_purchase_timestamp") >= col("dc.valid_from")) &
      (col("i.order_purchase_timestamp") <  col("dc.valid_to")),
      "left")
```

La condición `>= valid_from AND < valid_to` es el corazón del SCD2.

---

## 5. Role-playing Dimension

### Definición

Una **misma dimensión** referenciada **múltiples veces** desde el mismo fact en roles semánticamente distintos.

### Implementación en este proyecto

**`dim_date`** es referenciada **dos veces** desde `fact_order_items`:

| FK | Rol | Estado de la relación |
|---|---|---|
| `date_sk_purchase` | Fecha de compra de la orden | **Activa** |
| `date_sk_delivered` | Fecha de entrega al cliente | **Inactiva** |

Power BI **no permite múltiples relaciones activas** entre las mismas dos tablas. La segunda relación queda como inactiva (línea punteada en el modelo, ver `19-relationships-model.PNG`).

### Cómo usar la relación inactiva en DAX

Con `USERELATIONSHIP()` se puede invocar temporalmente la relación inactiva dentro de una medida:

```dax
Sales by Delivery Date =
CALCULATE(
    [Total Sales],
    USERELATIONSHIP(fact_order_items[date_sk_delivered], dim_date[date_sk])
)
```

Esto permite tener en el mismo dashboard:
- "Ventas por fecha de compra" → usa la relación activa (default).
- "Ventas por fecha de entrega" → invoca la relación inactiva vía la medida.

### Por qué importa

Sin esta técnica, tendrías que **duplicar `dim_date`** (una llamada `dim_purchase_date` y otra `dim_delivery_date`). Eso:

- Duplica el almacenamiento.
- Rompe la conformidad: si quieres comparar "purchase" vs "delivered" con `dim_reviews_date`, los slicers no se sincronizan.
- Mantenimiento: cualquier cambio en `dim_date` se replica dos veces.

Una sola `dim_date` con relaciones activa+inactiva es la solución elegante.

---

## Resumen de los 5 conceptos en una tabla

| Concepto | Implementación | Ventaja principal |
|---|---|---|
| Conformed | `dim_customer`, `dim_date` compartidas entre 2 facts | Slicers consistentes entre procesos |
| Degenerate | `order_id`, `order_item_id`, `review_id` en facts | No crea dims triviales con un solo campo |
| Junk | `dim_order_junk` agrupa 5 atributos categóricos pequeños | Limpia el fact y reduce dims triviales |
| SCD2 | `dim_customer` con `valid_from`, `valid_to`, `is_current` | Preserva historia de cambios |
| Role-playing | `dim_date` activa para purchase, inactiva para delivered | Reutiliza la misma dim para múltiples roles |
