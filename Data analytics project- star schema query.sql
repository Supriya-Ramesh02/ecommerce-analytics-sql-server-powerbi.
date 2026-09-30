--To check how many rows each table in the database has--

SELECT 'olist_customers_dataset' AS TableName, COUNT(*) AS Rows FROM dbo.olist_customers_dataset
UNION ALL SELECT 'olist_orders_dataset', COUNT(*) FROM dbo.olist_orders_dataset
UNION ALL SELECT 'olist_order_items_dataset', COUNT(*) FROM dbo.olist_order_items_dataset
UNION ALL SELECT 'olist_order_payments_dataset', COUNT(*) FROM dbo.olist_order_payments_dataset
UNION ALL SELECT 'olist_order_reviews_dataset', COUNT(*) FROM dbo.olist_order_reviews_dataset
UNION ALL SELECT 'olist_products_dataset', COUNT(*) FROM dbo.olist_products_dataset
UNION ALL SELECT 'olist_sellers_dataset', COUNT(*) FROM dbo.olist_sellers_dataset
UNION ALL SELECT 'olist_geolocation_dataset', COUNT(*) FROM dbo.olist_geolocation_dataset
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM dbo.product_category_name_translation;



/* ============================================================================
   OLIST STAR SCHEMA VIEWS — adapted to tables as imported via SSMS wizard
   Base tables: dbo.olist_customers_dataset, dbo.olist_orders_dataset,
                dbo.olist_order_items_dataset, dbo.olist_order_payments_dataset,
                dbo.olist_order_reviews_dataset, dbo.olist_products_dataset,
                dbo.olist_sellers_dataset, dbo.olist_geolocation_dataset,
                dbo.product_category_name_translation
   ============================================================================ */

USE KaggleDB;
GO

/* ----------------------------------------------------------------------
   DIM DATE
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.DimDate', 'V') IS NOT NULL DROP VIEW dbo.DimDate;
GO
CREATE VIEW dbo.DimDate AS
WITH Numbers AS (
    SELECT TOP (3000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
Dates AS (
    SELECT DATEADD(DAY, n, '2016-01-01') AS [Date]
    FROM Numbers
    WHERE DATEADD(DAY, n, '2016-01-01') <= '2019-12-31'
)
SELECT
    CONVERT(INT, FORMAT([Date], 'yyyyMMdd')) AS DateKey,
    [Date],
    DATEPART(YEAR, [Date])                    AS [Year],
    DATEPART(QUARTER, [Date])                  AS [Quarter],
    DATEPART(MONTH, [Date])                    AS MonthNumber,
    DATENAME(MONTH, [Date])                    AS MonthName,
    DATENAME(WEEKDAY, [Date])                  AS DayName,
    CASE WHEN DATEPART(WEEKDAY, [Date]) IN (1,7) THEN 1 ELSE 0 END AS IsWeekend
FROM Dates;
GO

/* ----------------------------------------------------------------------
   DIM CUSTOMER
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.DimCustomer', 'V') IS NOT NULL DROP VIEW dbo.DimCustomer;
GO
CREATE VIEW dbo.DimCustomer AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM dbo.olist_customers_dataset;
GO

/* ----------------------------------------------------------------------
   DIM SELLER
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.DimSeller', 'V') IS NOT NULL DROP VIEW dbo.DimSeller;
GO
CREATE VIEW dbo.DimSeller AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM dbo.olist_sellers_dataset;
GO

/* ----------------------------------------------------------------------
   DIM PRODUCT (with English category names)
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.DimProduct', 'V') IS NOT NULL DROP VIEW dbo.DimProduct;
GO
CREATE VIEW dbo.DimProduct AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS CategoryEnglish,
    p.product_category_name AS CategoryOriginal,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.product_photos_qty
FROM dbo.olist_products_dataset p
LEFT JOIN dbo.product_category_name_translation t ON p.product_category_name = t.product_category_name;
GO

/* ----------------------------------------------------------------------
   FACT ORDER ITEMS  (grain: one row per order line item)
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FactOrderItems', 'V') IS NOT NULL DROP VIEW dbo.FactOrderItems;
GO
CREATE VIEW dbo.FactOrderItems AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    CONVERT(INT, FORMAT(o.order_purchase_timestamp, 'yyyyMMdd'))       AS OrderDateKey,
    CONVERT(INT, FORMAT(o.order_delivered_customer_date, 'yyyyMMdd')) AS DeliveredDateKey,
    o.order_status,
    oi.price,
    oi.freight_value,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) AS DaysToDeliver,
    DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) AS DaysLateVsEstimate,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS IsLateDelivery
FROM dbo.olist_order_items_dataset oi
JOIN dbo.olist_orders_dataset o ON oi.order_id = o.order_id;
GO

/* ----------------------------------------------------------------------
   FACT PAYMENTS  (grain: one row per payment installment record per order)
   Kept separate from FactOrderItems to avoid double-counting payment_value
   across every item in a multi-item order.
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FactPayments', 'V') IS NOT NULL DROP VIEW dbo.FactPayments;
GO
CREATE VIEW dbo.FactPayments AS
SELECT
    op.order_id,
    op.payment_sequential,
    op.payment_type,
    op.payment_installments,
    op.payment_value,
    o.customer_id,
    CONVERT(INT, FORMAT(o.order_purchase_timestamp, 'yyyyMMdd')) AS OrderDateKey
FROM dbo.olist_order_payments_dataset op
JOIN dbo.olist_orders_dataset o ON op.order_id = o.order_id;
GO

/* ----------------------------------------------------------------------
   FACT REVIEWS  (grain: one row per review, i.e. per order)
---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FactReviews', 'V') IS NOT NULL DROP VIEW dbo.FactReviews;
GO
CREATE VIEW dbo.FactReviews AS
SELECT
    r.review_id,
    r.order_id,
    r.review_score,
    o.customer_id,
    CONVERT(INT, FORMAT(r.review_creation_date, 'yyyyMMdd')) AS ReviewDateKey,
    DATEDIFF(DAY, o.order_delivered_customer_date, r.review_creation_date) AS DaysDeliveryToReview
FROM dbo.olist_order_reviews_dataset r
JOIN dbo.olist_orders_dataset o ON r.order_id = o.order_id;
GO

PRINT 'Star-schema views created successfully against olist_*_dataset tables.';


IF OBJECT_ID('dbo.DimProduct', 'V') IS NOT NULL DROP VIEW dbo.DimProduct;
GO
CREATE VIEW dbo.DimProduct AS
SELECT
    p.product_id,
    COALESCE(t.column2, p.product_category_name, 'Unknown') AS CategoryEnglish,
    p.product_category_name AS CategoryOriginal,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.product_photos_qty
FROM dbo.olist_products_dataset p
LEFT JOIN dbo.product_category_name_translation t
    ON p.product_category_name = t.column1;
GO