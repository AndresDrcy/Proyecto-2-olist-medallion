# Medidas DAX del modelo semántico `sm_olist_gold`

Todas las medidas están organizadas en grupos lógicos. La captura `20-measurements-dax.PNG` muestra el panel del modelo con las medidas creadas.

---

## Grupo 1: Métricas de ventas

Construidas sobre `fact_order_items`. Son el núcleo financiero del modelo.

```dax
Total Sales = SUM(fact_order_items[price])
```
**Significado:** suma de precios de ítems. Excluye flete.

```dax
Total Freight = SUM(fact_order_items[freight_value])
```
**Significado:** suma de fletes.

```dax
Total GMV = SUM(fact_order_items[total_item_value])
```
**Significado:** GMV (Gross Merchandise Value) = `Total Sales + Total Freight`. Es la métrica de ingreso bruto que el cliente final pagó.

```dax
Total Orders = DISTINCTCOUNT(fact_order_items[order_id])
```
**Significado:** órdenes únicas. Usa la columna degenerada `order_id`.

```dax
Total Items Sold = COUNTROWS(fact_order_items)
```
**Significado:** ítems totales vendidos (suma de unidades, considerando que una orden con N ítems aporta N filas).

```dax
Average Order Value = DIVIDE([Total GMV], [Total Orders], 0)
```
**Significado:** AOV — valor promedio por orden.

---

## Grupo 2: Inteligencia temporal

Aprovechan que `dim_date` es un calendario continuo.

```dax
Sales YTD =
CALCULATE(
    [Total Sales],
    DATESYTD(dim_date[fecha])
)
```
**Significado:** ventas año a la fecha (Year-to-Date) hasta el contexto temporal actual.

```dax
Sales Previous Month =
CALCULATE(
    [Total Sales],
    PREVIOUSMONTH(dim_date[fecha])
)
```
**Significado:** ventas del mes anterior al filtrado actual.

```dax
Sales MoM % =
DIVIDE(
    [Total Sales] - [Sales Previous Month],
    [Sales Previous Month],
    BLANK()
)
```
**Significado:** variación porcentual mes contra mes (Month over Month).

---

## Grupo 3: Role-playing dimension

Aprovecha la relación inactiva entre `fact_order_items[date_sk_delivered]` y `dim_date[date_sk]`.

```dax
Sales by Delivery Date =
CALCULATE(
    [Total Sales],
    USERELATIONSHIP(fact_order_items[date_sk_delivered], dim_date[date_sk])
)
```
**Significado:** ventas atribuidas a la fecha de **entrega** (no de compra). Permite responder "¿cuánto entregamos en marzo?" vs la pregunta default "¿cuánto compraron en marzo?".

**Demostración:** comparar `Total Sales` vs `Sales by Delivery Date` con un slicer en `dim_date[mes_anio]` muestra el "lag de cumplimiento" entre la compra y la entrega.

---

## Grupo 4: Métricas de reviews

Construidas sobre `fact_reviews`. **Demuestran la dimensión conformada en acción** — comparten `dim_customer` y `dim_date` con `fact_order_items`.

```dax
Total Reviews = COUNTROWS(fact_reviews)
```
**Significado:** cantidad total de reviews en el contexto.

```dax
Average Review Score = AVERAGE(fact_reviews[review_score])
```
**Significado:** promedio de calificación (1-5).

```dax
% Reviews 5 Stars =
DIVIDE(
    CALCULATE([Total Reviews], fact_reviews[review_score] = 5),
    [Total Reviews],
    0
)
```
**Significado:** porcentaje de reviews con score perfecto.

```dax
Average Response Time (h) =
AVERAGE(fact_reviews[response_time_hours])
```
**Significado:** tiempo promedio (en horas) entre creación del review y la respuesta del vendedor.

---

## Grupo 5: Cross-fact (dimensión conformada)

Estas son las medidas que **demuestran la conformidad** entre ambos facts. Cuando un slicer en `dim_customer[state]` se aplica, ambas medidas se filtran consistentemente.

```dax
Sales per Customer =
DIVIDE([Total Sales], DISTINCTCOUNT(fact_order_items[customer_sk]), 0)
```
**Significado:** valor promedio de ventas por cliente único en el contexto filtrado.

```dax
Reviews per Customer =
DIVIDE([Total Reviews], DISTINCTCOUNT(fact_reviews[customer_sk]), 0)
```
**Significado:** cantidad promedio de reviews por cliente único en el contexto filtrado.

### Uso conjunto en el dashboard página 2

Filtrando por `dim_customer[state] = "SP"`:
- `Sales per Customer` cae al estado SP (filtra `fact_order_items`).
- `Reviews per Customer` cae al estado SP (filtra `fact_reviews`).

Ambos comparten el mismo slicer. Esa es **literalmente** la ventaja de la dimensión conformada: un solo filtro, dos facts.

Si `dim_customer` no fuera conformada, necesitarías mantener dos versiones del slicer y manualmente sincronizarlas. Confuso para el usuario y propenso a errores.

---

## Convenciones aplicadas

- **Nombres en inglés:** estándar de la industria para medidas DAX.
- **Uso de `DIVIDE` en lugar de `/`:** `DIVIDE` maneja división por cero retornando un valor seguro (0 o BLANK), evitando errores.
- **`DISTINCTCOUNT` sobre claves naturales** (`order_id`) en lugar de surrogate keys cuando se cuenta entidades del negocio.
- **`CALCULATE` con condiciones explícitas** para medidas filtradas (no se usan iteradores complejos).
- **Sin tablas calculadas DAX:** se evitan deliberadamente para mantener Direct Lake operativo. Filtros como "current customer" se resuelven con la vista SQL `v_dim_customer_current` en lugar de `FILTER()` en DAX.

---

## Medidas posibles a agregar

- **`Customer Retention Rate`:** clientes que compraron dos veces o más en un período. Requiere lógica de DISTINCTCOUNT con ventana móvil.
- **`Average Delivery Lag (days)`:** ya viene precalculado en silver_orders como `delivery_delay_days`. Bastaría exponerlo.
- **`Revenue by Cohort`:** análisis de cohortes basado en mes de primera compra de cada cliente.
- **`Top 10 Categories`:** medida con `TOPN` filtrando por `dim_product[category]`.
