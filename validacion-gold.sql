-- ========================================================================
-- Queries de validación para el modelo Gold del proyecto Olist
-- ------------------------------------------------------------------------
-- Ejecutar en el SQL Endpoint de lh_olist_gold.
-- Sirven como (a) tests manuales post-build, (b) referencia para construir
--   tests automatizados en v2, y (c) demostración de integridad del modelo
--   para reviewers técnicos.
-- ========================================================================


-- ========================================================================
-- 1. VOLÚMENES POR TABLA
-- ------------------------------------------------------------------------
-- Conteos de cada tabla del modelo. Útil para detectar pérdida de filas
-- entre ejecuciones o para validar contra los conteos esperados.
-- ========================================================================

SELECT 'fact_order_items' AS tabla, COUNT(*) AS filas FROM fact_order_items
UNION ALL SELECT 'fact_reviews',    COUNT(*) FROM fact_reviews
UNION ALL SELECT 'dim_customer',    COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_product',     COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_seller',      COUNT(*) FROM dim_seller
UNION ALL SELECT 'dim_order_junk',  COUNT(*) FROM dim_order_junk
UNION ALL SELECT 'dim_date',        COUNT(*) FROM dim_date
ORDER BY tabla;


-- ========================================================================
-- 2. SCD2 — CLIENTES CON HISTORIA (múltiples versiones)
-- ------------------------------------------------------------------------
-- Identifica clientes que tuvieron al menos un cambio trackeado.
-- Sirve para demostrar que el SCD2 detectó historia real, no es teatral.
-- ========================================================================

SELECT
    customer_natural_id,
    COUNT(*) AS versiones,
    MIN(valid_from) AS primera_version,
    MAX(valid_from) AS ultima_version
FROM dim_customer
GROUP BY customer_natural_id
HAVING COUNT(*) > 1
ORDER BY versiones DESC, customer_natural_id;


-- ========================================================================
-- 3. SCD2 — HISTORIA COMPLETA DE UN CLIENTE EJEMPLO
-- ------------------------------------------------------------------------
-- Reemplazar el ID por uno real de la query anterior para ver todas
-- las versiones cronológicamente.
-- ========================================================================

SELECT
    customer_sk,
    customer_natural_id,
    city,
    state,
    zip_prefix,
    valid_from,
    valid_to,
    is_current
FROM dim_customer
WHERE customer_natural_id = '<<reemplazar_por_un_id_real>>'
ORDER BY valid_from;


-- ========================================================================
-- 4. INTEGRIDAD REFERENCIAL — fact_order_items
-- ------------------------------------------------------------------------
-- Cuenta huérfanos (filas en el fact con FK que no existe en la dim).
-- Resultado esperado: 0 huérfanos en todas las relaciones del fact.
-- ========================================================================

-- Customer
SELECT 'customer_sk -> dim_customer' AS relacion, COUNT(*) AS huerfanos
FROM fact_order_items f
LEFT ANTI JOIN dim_customer d ON f.customer_sk = d.customer_sk

UNION ALL SELECT 'product_sk -> dim_product', COUNT(*)
FROM fact_order_items f
LEFT ANTI JOIN dim_product d ON f.product_sk = d.product_sk

UNION ALL SELECT 'seller_sk -> dim_seller', COUNT(*)
FROM fact_order_items f
LEFT ANTI JOIN dim_seller d ON f.seller_sk = d.seller_sk

UNION ALL SELECT 'junk_sk -> dim_order_junk', COUNT(*)
FROM fact_order_items f
LEFT ANTI JOIN dim_order_junk d ON f.junk_sk = d.junk_sk

UNION ALL SELECT 'date_sk_purchase -> dim_date', COUNT(*)
FROM fact_order_items f
LEFT ANTI JOIN dim_date d ON f.date_sk_purchase = d.date_sk;


-- ========================================================================
-- 5. INTEGRIDAD REFERENCIAL — fact_reviews
-- ------------------------------------------------------------------------
-- En fact_reviews se aceptan hasta 30 huérfanos en customer_sk (0.03%)
-- por inconsistencias documentadas del dataset Olist (review_creation_date
-- anterior al order_purchase_timestamp). Ver README — Hallazgos de calidad.
-- ========================================================================

SELECT 'customer_sk -> dim_customer' AS relacion,
       COUNT(*) AS huerfanos,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_reviews), 3) AS pct
FROM fact_reviews f
LEFT ANTI JOIN dim_customer d ON f.customer_sk = d.customer_sk

UNION ALL SELECT 'date_sk_review -> dim_date', COUNT(*), 
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_reviews), 3)
FROM fact_reviews f
LEFT ANTI JOIN dim_date d ON f.date_sk_review = d.date_sk;


-- ========================================================================
-- 6. ANÁLISIS CROSS-FACT (demostración de dimensión conformada)
-- ------------------------------------------------------------------------
-- Combina ventas y reviews por estado, usando dim_customer conformada.
-- Esta query es la versión SQL del visual de la página 2 del dashboard.
-- ========================================================================

SELECT
    dc.state,
    COUNT(DISTINCT foi.order_id)         AS total_orders,
    ROUND(SUM(foi.price), 2)             AS total_sales,
    ROUND(AVG(fr.review_score), 2)       AS avg_review_score,
    COUNT(DISTINCT fr.review_id)         AS total_reviews,
    ROUND(SUM(foi.price) / NULLIF(COUNT(DISTINCT foi.customer_sk), 0), 2)
                                          AS sales_per_customer
FROM fact_order_items foi
JOIN dim_customer dc ON foi.customer_sk = dc.customer_sk
LEFT JOIN fact_reviews fr ON fr.customer_sk = dc.customer_sk
WHERE dc.is_current = True
GROUP BY dc.state
ORDER BY total_sales DESC
LIMIT 15;


-- ========================================================================
-- 7. JUNK DIMENSION — distribución de combinaciones
-- ------------------------------------------------------------------------
-- Top combinaciones más frecuentes en fact_order_items. Útil para
-- entender el perfil operacional del negocio.
-- ========================================================================

SELECT
    doj.order_status,
    doj.delivery_status_bucket,
    doj.payment_type,
    doj.installments_bucket,
    doj.has_review,
    COUNT(*) AS items_count,
    ROUND(SUM(foi.price), 2) AS total_sales
FROM fact_order_items foi
JOIN dim_order_junk doj ON foi.junk_sk = doj.junk_sk
GROUP BY
    doj.order_status,
    doj.delivery_status_bucket,
    doj.payment_type,
    doj.installments_bucket,
    doj.has_review
ORDER BY items_count DESC
LIMIT 20;


-- ========================================================================
-- 8. CALIDAD DE DATOS — productos sin categoría
-- ------------------------------------------------------------------------
-- Identifica los 610 productos donde la categoría es "unknown"
-- (NULL en origen, manejado en Silver con coalesce).
-- ========================================================================

SELECT
    'productos_sin_categoria' AS metrica,
    COUNT(*) AS cantidad,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dim_product), 2) AS pct_del_total
FROM dim_product
WHERE category = 'unknown';


-- ========================================================================
-- 9. ROLE-PLAYING DIMENSION — gap entre compra y entrega
-- ------------------------------------------------------------------------
-- Demuestra el uso conceptual de las dos relaciones (activa e inactiva)
-- con dim_date desde fact_order_items.
-- ========================================================================

SELECT
    dp.mes_anio AS mes_compra,
    COUNT(DISTINCT foi.order_id) AS ordenes_compradas,
    ROUND(AVG(DATEDIFF(dd.fecha, dp.fecha)), 1) AS dias_promedio_a_entrega
FROM fact_order_items foi
JOIN dim_date dp ON foi.date_sk_purchase = dp.date_sk
LEFT JOIN dim_date dd ON foi.date_sk_delivered = dd.date_sk
WHERE foi.date_sk_delivered IS NOT NULL
GROUP BY dp.mes_anio
ORDER BY dp.mes_anio;


-- ========================================================================
-- 10. VALIDACIÓN DE LA VISTA v_dim_customer_current
-- ------------------------------------------------------------------------
-- Confirma que la vista solo retorna versiones vigentes.
-- ========================================================================

SELECT
    'dim_customer total versiones' AS metrica, COUNT(*) AS valor FROM dim_customer
UNION ALL
SELECT 'dim_customer is_current=True', COUNT(*) FROM dim_customer WHERE is_current = True
UNION ALL
SELECT 'v_dim_customer_current rows', COUNT(*) FROM v_dim_customer_current;
-- Las dos últimas filas deberían tener el mismo conteo.
