# Modelo dimensional — Diccionario de datos

Documento de referencia del modelo estrella en `lh_olist_gold`. Sirve para entender qué representa cada tabla, qué granos manejan los facts, y qué reglas de relación aplican.

---

## Visión general

**2 tablas de hechos** + **5 dimensiones** + **1 vista** (para análisis de clientes vigentes).

```
                              dim_date
                                 │
                          ┌──────┴──────┐
                          │             │
              date_sk_purchase   date_sk_review
              (activa)           (activa)
                          │             │
   ┌──────────────────────┴──┐       ┌──┴─────────────┐
   │                         │       │                │
   │   fact_order_items      │       │  fact_reviews  │
   │                         │       │                │
   └──┬────────┬──────┬──────┘       └────┬───────────┘
      │        │      │                   │
      │     product_sk│                   │
      │        │      │                   │
      │   dim_product │                   │
      │              seller_sk            │
      │               │                   │
      │           dim_seller              │
      │                                   │
      │              junk_sk              │
      │               │                   │
      │           dim_order_junk          │
      │                                   │
      └───────────────┬───────────────────┘
                      │
                customer_sk
                      │
                dim_customer (CONFORMED — usado por ambos facts)
                      │
                      ▼
            v_dim_customer_current (vista SQL — solo clientes is_current=True)
```

Además: relación **inactiva** entre `fact_order_items[date_sk_delivered]` y `dim_date[date_sk]` (role-playing — activada vía `USERELATIONSHIP` en DAX).

---

## Tablas de hechos

### `fact_order_items`

**Grain:** una fila por ítem de orden. Una orden con 3 productos genera 3 filas.

| Columna | Tipo | Rol | Descripción |
|---|---|---|---|
| `order_id` | string | **DEGENERATE** | ID de orden (sin dim propia) |
| `order_item_id` | int | **DEGENERATE** | Secuencia del ítem dentro de la orden |
| `customer_sk` | bigint | FK | → `dim_customer` (SCD2-aware: versión vigente al momento del `order_purchase_timestamp`) |
| `product_sk` | bigint | FK | → `dim_product` |
| `seller_sk` | bigint | FK | → `dim_seller` |
| `junk_sk` | bigint | FK | → `dim_order_junk` |
| `date_sk_purchase` | int | FK | → `dim_date` (**activa**) — fecha de compra |
| `date_sk_delivered` | int | FK | → `dim_date` (**inactiva**) — fecha de entrega; role-playing |
| `price` | double | MEASURE | Precio del ítem |
| `freight_value` | double | MEASURE | Flete del ítem |
| `total_item_value` | double | MEASURE | `price + freight_value` (precalculado) |

**Conteo aproximado:** ~112,650 filas.

---

### `fact_reviews`

**Grain:** una fila por review. Una orden tiene 0 o 1 review.

| Columna | Tipo | Rol | Descripción |
|---|---|---|---|
| `review_id` | string | **DEGENERATE** | ID del review (sin dim propia) |
| `order_id` | string | **DEGENERATE** | ID de orden reseñada (sin dim propia, no es FK) |
| `customer_sk` | bigint | FK | → `dim_customer` (**CONFORMED** con `fact_order_items`, SCD2-aware respecto a `review_creation_date`) |
| `date_sk_review` | int | FK | → `dim_date` (**CONFORMED**) — fecha del review |
| `review_score` | int | MEASURE | 1-5 |
| `response_time_hours` | double | MEASURE | Horas entre `review_creation_date` y `review_answer_timestamp` |
| `has_comment` | boolean | MEASURE | Flag — review trae texto adicional |
| `comment_length` | int | MEASURE | Longitud del comentario (0 si vacío) |

**Conteo aproximado:** ~99,000 filas (`silver_order_reviews` después de dedup).

---

## Dimensiones

### `dim_date` — Conformed, calendario continuo

**Grano:** una fila por día calendario, desde `MIN(order_purchase)` hasta `MAX(review_creation)`.

| Columna | Tipo | Descripción |
|---|---|---|
| `date_sk` | int | **PK** — formato YYYYMMDD (ej: 20170315) |
| `fecha` | date | Fecha calendario |
| `anio` | int | Año (4 dígitos) |
| `trimestre` | int | 1-4 |
| `mes_numero` | int | 1-12 |
| `mes_nombre` | string | Nombre del mes (English) |
| `mes_anio` | string | "YYYY-MM" — para slicers de mes |
| `semana_anio` | int | Semana ISO del año |
| `dia_mes` | int | 1-31 |
| `dia_semana_num` | int | 1-7 (Sunday=1) |
| `dia_nombre` | string | Nombre del día |
| `es_fin_semana` | boolean | True para sábado/domingo |

**Conteo aproximado:** ~720 filas (≈2 años).

---

### `dim_customer` — Conformed + SCD Tipo 2

**Grano:** una fila por **versión** de un cliente. Un mismo cliente puede tener múltiples filas si cambió `city`/`state`/`zip` entre órdenes.

| Columna | Tipo | Descripción |
|---|---|---|
| `customer_sk` | bigint | **PK** — surrogate, única por versión |
| `customer_natural_id` | string | Natural key (= `customer_unique_id` de Olist), única por persona |
| `city` | string | Ciudad de esta versión (lowercased, trimmed) |
| `state` | string | Estado de esta versión |
| `zip_prefix` | int | Prefijo postal de esta versión |
| `attribute_hash` | string | SHA-256 de city+state+zip para detección de cambios |
| `valid_from` | timestamp | Inicio de vigencia de esta versión |
| `valid_to` | timestamp | Fin de vigencia (`9999-12-31` si actual) |
| `is_current` | boolean | True solo para la versión vigente |

**Conteo aproximado:** ~96,000+ filas (similar a clientes únicos, más algunas extras por cambios).

---

### `dim_product` — SCD Tipo 1

**Grano:** una fila por producto. Sobreescritura (sin historial).

| Columna | Tipo | Descripción |
|---|---|---|
| `product_sk` | bigint | **PK** — surrogate |
| `product_natural_id` | string | `product_id` original de Olist |
| `category` | string | Categoría en inglés (post-traducción + `"unknown"` para NULLs) |
| `product_weight_g` | double | Peso en gramos (imputado con mediana si era NULL en origen) |
| `product_volume_cm3` | double | Volumen calculado = length × height × width |
| `size_category` | string | Bucketización: `Small` / `Medium` / `Large` / `Extra Large` |

**Conteo aproximado:** ~32,951 filas.

---

### `dim_seller` — SCD Tipo 1

**Grano:** una fila por vendedor.

| Columna | Tipo | Descripción |
|---|---|---|
| `seller_sk` | bigint | **PK** — surrogate |
| `seller_natural_id` | string | `seller_id` original de Olist |
| `zip_prefix` | int | Prefijo postal |
| `city` | string | Ciudad (lowercased) |
| `state` | string | Estado |

**Conteo aproximado:** ~3,095 filas.

---

### `dim_order_junk` — Junk Dimension

**Grano:** una fila por **combinación única observada** de los 5 atributos. No es el producto cartesiano completo.

| Columna | Tipo | Descripción |
|---|---|---|
| `junk_sk` | bigint | **PK** — surrogate |
| `order_status` | string | Status de la orden (delivered, shipped, canceled, etc.) |
| `delivery_status_bucket` | string | `Not Delivered` / `On time` / `Late <=7d` / `Late >7d` |
| `payment_type` | string | `credit_card` / `boleto` / `voucher` / `debit_card` / `none` |
| `installments_bucket` | string | `1` / `2-5` / `6-12` / `13+` / `none` |
| `has_review` | boolean | Flag — la orden tiene review |
| `attribute_hash` | string | SHA-256 de las 5 columnas (no usado en queries, útil para lineage) |

**Conteo:** 107 combinaciones (vs 1024 teóricas). Ver explicación en `conceptos-dimensionales.md`.

---

### `v_dim_customer_current` — Vista SQL (no es tabla)

**Definición:**
```sql
CREATE VIEW v_dim_customer_current AS
SELECT * FROM dim_customer WHERE is_current = True;
```

**Propósito:** slicers de "cliente vigente" en el dashboard sin necesidad de filtrar `is_current = True` en cada query. Misma estructura que `dim_customer`.

**Modo en el semantic model:** DirectQuery (es una vista, no tabla Delta). El resto del modelo es Direct Lake → modelo compuesto.

**Importante:** NO se crean relaciones desde esta vista hacia los facts. Es para slicers únicamente. Las relaciones con facts las maneja `dim_customer`.

---

## Relaciones del modelo semántico

### Desde `fact_order_items`

| FK | → Dim | Cardinalidad | Estado | Filter Direction |
|---|---|---|---|---|
| `customer_sk` | `dim_customer[customer_sk]` | * → 1 | Activa | Single |
| `product_sk` | `dim_product[product_sk]` | * → 1 | Activa | Single |
| `seller_sk` | `dim_seller[seller_sk]` | * → 1 | Activa | Single |
| `junk_sk` | `dim_order_junk[junk_sk]` | * → 1 | Activa | Single |
| `date_sk_purchase` | `dim_date[date_sk]` | * → 1 | **Activa** | Single |
| `date_sk_delivered` | `dim_date[date_sk]` | * → 1 | **Inactiva** | Single |

### Desde `fact_reviews`

| FK | → Dim | Cardinalidad | Estado |
|---|---|---|---|
| `customer_sk` | `dim_customer[customer_sk]` | * → 1 | Activa |
| `date_sk_review` | `dim_date[date_sk]` | * → 1 | Activa |

### `v_dim_customer_current`

**Sin relaciones hacia facts.** Solo se usa como tabla de slicers.

---

## Reglas de integridad

1. **`dim_date` cubre el rango completo de eventos.** No debería haber `date_sk` en facts que no exista en `dim_date`.

2. **`dim_customer.customer_sk` es único por VERSIÓN, no por persona.** El mismo `customer_natural_id` puede aparecer en múltiples filas si tuvo cambios.

3. **Lookups SCD2-aware:** `fact_order_items.customer_sk` se asigna por la versión vigente al momento de `order_purchase_timestamp`. `fact_reviews.customer_sk` se asigna por la versión vigente al momento de `review_creation_date`.

4. **Umbral tolerable de huérfanos:** la validación acepta hasta 0.1% de huérfanos por relación. Esto cubre los 30 reviews documentados con anomalías de timestamp en origen.

5. **Las columnas degeneradas (`order_id`, `order_item_id`, `review_id`) no tienen integridad referencial dentro del modelo** — apuntan a sistemas operacionales externos (Olist).

Queries de validación de integridad en [`validacion-gold.sql`](./validacion-gold.sql).
