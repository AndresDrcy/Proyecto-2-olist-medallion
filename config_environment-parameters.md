# Parámetros por ambiente — Configuración de notebooks

Documento de referencia para los parámetros que aceptan los notebooks del proyecto. Cada notebook tiene una **parameters cell** en la posición 2 cuyo contenido puede ser sobre-escrito en tiempo de ejecución desde un Data Pipeline.

---

## Por qué parametrizar

En entornos empresariales, **el mismo código** corre en múltiples ambientes (dev, test, prod) contra diferentes Lakehouses. Hardcodear nombres de Lakehouses en el notebook impide esa promoción. La parametrización resuelve esto sin duplicar código.

Cuando un Data Pipeline llama al notebook, los valores de la parameters cell **se sobre-escriben** con los del pipeline antes de ejecutar el resto del notebook. Si el notebook se ejecuta manualmente (Run), usa los defaults del documento.

---

## Cómo se marca una parameters cell en Fabric

1. Ir a la celda que contiene los parámetros (típicamente celda 2).
2. Click en los 3 puntos (⋯) del lado derecho de la celda.
3. Seleccionar **"Toggle parameter cell"**.
4. La celda muestra una etiqueta visible **"Parameters"**.

Si la etiqueta no aparece, el override desde pipeline no funcionará.

---

## Parámetros por notebook

### Notebook `01-bronze-ingestion`

```python
BRONZE_LAKEHOUSE = "lh_olist_bronze"
RAW_FILES_PATH = "raw"
WRITE_MODE = "overwrite"
```

| Parámetro | Tipo | Propósito |
|---|---|---|
| `BRONZE_LAKEHOUSE` | str | Lakehouse de destino donde se escriben las tablas Bronze |
| `RAW_FILES_PATH` | str | Subruta dentro de `Files/` donde residen los CSVs |
| `WRITE_MODE` | str | `overwrite` o `append` |

---

### Notebook `02-silver-transformation`

```python
BRONZE_LAKEHOUSE = "lh_olist_bronze"
SILVER_LAKEHOUSE = "lh_olist_silver"
WRITE_MODE = "overwrite"
```

| Parámetro | Tipo | Propósito |
|---|---|---|
| `BRONZE_LAKEHOUSE` | str | Lakehouse fuente (de lectura) |
| `SILVER_LAKEHOUSE` | str | Lakehouse destino (de escritura) — debe ser el default del notebook |
| `WRITE_MODE` | str | `overwrite` o `append` |

---

### Notebook `03-gold-dimensions`

```python
SILVER_LAKEHOUSE = "lh_olist_silver"
GOLD_LAKEHOUSE = "lh_olist_gold"
WRITE_MODE = "overwrite"
```

| Parámetro | Tipo | Propósito |
|---|---|---|
| `SILVER_LAKEHOUSE` | str | Lakehouse fuente (Silver) |
| `GOLD_LAKEHOUSE` | str | Lakehouse destino (Gold) — debe ser el default |
| `WRITE_MODE` | str | `overwrite` o `append` |

---

### Notebook `04-gold-facts`

```python
SILVER_LAKEHOUSE = "lh_olist_silver"
GOLD_LAKEHOUSE = "lh_olist_gold"
WRITE_MODE = "overwrite"
```

| Parámetro | Tipo | Propósito |
|---|---|---|
| `SILVER_LAKEHOUSE` | str | Lakehouse fuente (Silver) — para datos transaccionales |
| `GOLD_LAKEHOUSE` | str | Lakehouse destino y también fuente de dimensiones |
| `WRITE_MODE` | str | `overwrite` o `append` |

---

## Valores recomendados por ambiente

### Dev (default actual)

```yaml
BRONZE_LAKEHOUSE: lh_olist_bronze
SILVER_LAKEHOUSE: lh_olist_silver
GOLD_LAKEHOUSE: lh_olist_gold
RAW_FILES_PATH: raw
WRITE_MODE: overwrite
```

### Test (ejemplo conceptual)

```yaml
BRONZE_LAKEHOUSE: lh_olist_bronze_test
SILVER_LAKEHOUSE: lh_olist_silver_test
GOLD_LAKEHOUSE: lh_olist_gold_test
RAW_FILES_PATH: raw_test_subset
WRITE_MODE: overwrite
```

**Notas:** ambiente de prueba típicamente trabaja con un subconjunto de datos para acelerar iteración. La carpeta `raw_test_subset/` contendría una muestra ~10% del dataset completo.

### Prod (ejemplo conceptual)

```yaml
BRONZE_LAKEHOUSE: lh_olist_bronze_prod
SILVER_LAKEHOUSE: lh_olist_silver_prod
GOLD_LAKEHOUSE: lh_olist_gold_prod
RAW_FILES_PATH: incremental/YYYY-MM-DD
WRITE_MODE: append
```

**Notas:** en producción real, el `WRITE_MODE` cambia a `append` para soportar cargas incrementales. El `RAW_FILES_PATH` apunta a la carpeta del lote del día. Esto requiere que los notebooks tengan también lógica de MERGE (no implementada en este proyecto, ver Limitaciones del README).

---

## Cómo sobre-escribir desde un Data Pipeline

1. Desde el workspace, crear un Data Pipeline nuevo.
2. Agregar actividad **Notebook** → seleccionar el notebook target.
3. En la pestaña **Settings** de la actividad → expandir **"Base parameters"**.
4. Agregar pares clave/valor. **Las claves deben coincidir exactamente** (case-sensitive) con los nombres de las variables en la parameters cell.

Ejemplo para promover `02-silver-transformation` a test:

| Name | Value |
|---|---|
| `BRONZE_LAKEHOUSE` | `lh_olist_bronze_test` |
| `SILVER_LAKEHOUSE` | `lh_olist_silver_test` |
| `WRITE_MODE` | `overwrite` |

Al ejecutar el pipeline, Fabric inyecta esos valores en la parameters cell y el resto del notebook los usa.

---

## Verificación post-modificación

Para confirmar que la parameters cell está bien configurada:

1. Abrir el notebook.
2. Verificar que la celda 2 muestra el badge **"Parameters"** en la parte superior.
3. Ejecutar `print(BRONZE_LAKEHOUSE)` (o el parámetro correspondiente) en una celda nueva para confirmar el valor actual.

Si la celda 2 no tiene el badge, los overrides del pipeline serán ignorados silenciosamente.

---

## Limitación conocida

El proyecto actual usa `WRITE_MODE = "overwrite"` en todos los notebooks. Para promoción a un ambiente prod con cargas incrementales reales, los notebooks necesitan refactor:

- Detección de cambios con hash o timestamps.
- Patrón MERGE INTO de Delta en lugar de overwrite.
- Particionado de tablas grandes.
- Soporte de "high water mark" para no reprocesar lo ya cargado.

Esto está documentado en la sección de Mejoras posibles del README principal.
