# Dataset Olist Brazilian E-Commerce

Esta carpeta contiene una **copia local** del dataset Olist usado por el proyecto. Se incluye en el repositorio para facilitar reproducibilidad inmediata sin requerir descargar desde Kaggle.

---

## Fuente original

**Brazilian E-Commerce Public Dataset by Olist**
URL: <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>

Publicado por Olist Store, una marketplace brasileña, en colaboración con la comunidad de Kaggle. Cubre órdenes reales entre 2016 y 2018, con todos los datos personales identificables (PII) anonimizados.

---

## Licencia

**Creative Commons Attribution Non-Commercial Share-Alike 4.0** (CC BY-NC-SA 4.0)

Términos clave:
- ✅ Atribuir a Olist (crédito obligatorio).
- ✅ Compartir bajo la misma licencia.
- ❌ **No usar para fines comerciales.**

Más detalle: <https://creativecommons.org/licenses/by-nc-sa/4.0/>

---

## Archivos incluidos

Los 8 archivos utilizados por el proyecto:

| Archivo | Tamaño aprox | Descripción |
|---|---|---|
| `olist_customers_dataset.csv` | 8.6 MB | Clientes (uno por orden) |
| `olist_orders_dataset.csv` | 16.8 MB | Órdenes con timestamps de compra/aprobación/envío/entrega |
| `olist_order_items_dataset.csv` | 14.7 MB | Ítems por orden (multi-fila por orden) |
| `olist_order_payments_dataset.csv` | 5.5 MB | Pagos por orden (multi-fila si hay varios métodos) |
| `olist_order_reviews_dataset.csv` | 13.8 MB | Reviews (1-5 estrellas + comentario opcional) |
| `olist_products_dataset.csv` | 2.3 MB | Productos con categoría y dimensiones físicas |
| `olist_sellers_dataset.csv` | 167 KB | Vendedores con ubicación |
| `product_category_name_translation.csv` | 3 KB | Lookup PT → EN de categorías |

**Total:** ~62 MB.

**Excluido:** `olist_geolocation_dataset.csv` (~60 MB, 1M filas). Decisión de scope — no aporta a los conceptos dimensionales que el proyecto demuestra. Si querés agregarlo, descárgalo desde Kaggle.

---

## Cómo obtener una versión actualizada

Si querés re-descargar desde la fuente (por ejemplo, si Olist publica una versión nueva):

1. Crear cuenta en Kaggle (gratis).
2. Visitar <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>.
3. Click en **"Download"** (arriba derecha) → descarga un ZIP de ~45 MB.
4. Descomprimir y reemplazar los archivos de esta carpeta.

Los conteos pueden variar ligeramente entre versiones del dataset.

---

## Cómo se carga en el proyecto

Los CSVs se suben a Microsoft Fabric en la siguiente ruta:

```
lh_olist_bronze/Files/raw/
├── olist_customers_dataset.csv
├── olist_orders_dataset.csv
├── olist_order_items_dataset.csv
├── olist_order_payments_dataset.csv
├── olist_order_reviews_dataset.csv
├── olist_products_dataset.csv
├── olist_sellers_dataset.csv
└── product_category_name_translation.csv
```

El notebook `01-bronze-ingestion` itera sobre estos archivos y los persiste como tablas Delta `bronze_*` en el mismo Lakehouse.

---

## Notas de calidad de datos conocidas

Identificadas durante la construcción del proyecto y documentadas en el README principal:

1. **610 productos sin categoría** (`product_category_name = NULL` en origen). Manejados como `category = "unknown"` en Silver.

2. **30 reviews con timestamps inconsistentes** (`review_creation_date` anterior al `order_purchase_timestamp` de la orden asociada). Manejados con umbral tolerable del 0.1% en validación de Gold.

Estas anomalías son del **sistema fuente**, no del pipeline. Se aceptan documentándolas.

---

## Atribución requerida (para publicación)

Si republicás resultados derivados de este dataset en cualquier formato, incluí:

> **Fuente:** Brazilian E-Commerce Public Dataset by Olist
> Publicado por Olist Store en Kaggle bajo licencia CC BY-NC-SA 4.0
> <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce>
