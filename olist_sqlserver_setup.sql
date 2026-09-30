/* ============================================================================
   OLIST BRAZILIAN E-COMMERCE PROJECT — SQL SERVER SETUP
   Source: 9 CSVs from kaggle.com/datasets/olistbr/brazilian-ecommerce
   Step 1: create staging tables matching each CSV
   Step 2: bulk-load the CSVs
   Step 3: build star-schema views on top (same pattern as AdventureWorks)
   ============================================================================ */

CREATE DATABASE OlistEcommerce;
GO
USE OlistEcommerce;
GO

/* ----------------------------------------------------------------------
   STEP 1 — STAGING TABLES (one per CSV, columns match Kaggle headers)
---------------------------------------------------------------------- */

CREATE TABLE stg_customers (
    customer_id             VARCHAR(50)  NOT NULL,
    customer_unique_id      VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city           VARCHAR(100),
    customer_state          VARCHAR(5)
);

CREATE TABLE stg_orders (
    order_id                      VARCHAR(50) NOT NULL,
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(30),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME,
    order_delivered_carrier_date  DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

CREATE TABLE stg_order_items (
    order_id            VARCHAR(50),
    order_item_id        INT,
    product_id           VARCHAR(50),
    seller_id             VARCHAR(50),
    shipping_limit_date   DATETIME,
    price                 DECIMAL(10,2),
    freight_value         DECIMAL(10,2)
);

CREATE TABLE stg_order_payments (
    order_id             VARCHAR(50),
    payment_sequential    INT,
    payment_type          VARCHAR(30),
    payment_installments  INT,
    payment_value         DECIMAL(10,2)
);

CREATE TABLE stg_order_reviews (
    review_id                VARCHAR(50),
    order_id                  VARCHAR(50),
    review_score               INT,
    review_comment_title       NVARCHAR(200),
    review_comment_message     NVARCHAR(MAX),
    review_creation_date       DATETIME,
    review_answer_timestamp    DATETIME
);

CREATE TABLE stg_products (
    product_id                    VARCHAR(50) NOT NULL,
    product_category_name         VARCHAR(100),
    product_name_lenght           INT,
    product_description_lenght    INT,
    product_photos_qty            INT,
    product_weight_g              INT,
    product_length_cm             INT,
    product_height_cm             INT,
    product_width_cm              INT
);

CREATE TABLE stg_sellers (
    seller_id               VARCHAR(50) NOT NULL,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state             VARCHAR(5)
);

CREATE TABLE stg_geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat               DECIMAL(11,8),
    geolocation_lng               DECIMAL(11,8),
    geolocation_city               VARCHAR(100),
    geolocation_state              VARCHAR(5)
);

CREATE TABLE stg_category_translation (
    product_category_name          VARCHAR(100),
    product_category_name_english  VARCHAR(100)
);
GO

/* ----------------------------------------------------------------------
   STEP 2 — BULK LOAD
   Adjust the file path to wherever you extracted the Kaggle CSVs.
   Requires SQL Server to have read access to that folder (local path if
   SQL Server runs on your machine; a UNC/share path if remote).
---------------------------------------------------------------------- */

BULK INSERT stg_customers
FROM 'C:\OlistData\olist_customers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_orders
FROM 'C:\OlistData\olist_orders_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_order_items
FROM 'C:\OlistData\olist_order_items_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_order_payments
FROM 'C:\OlistData\olist_order_payments_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_order_reviews
FROM 'C:\OlistData\olist_order_reviews_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK,
      FIELDQUOTE = '"', ROWTERMINATOR = '0x0a');  -- review text has commas/newlines; quoted CSV

BULK INSERT stg_products
FROM 'C:\OlistData\olist_products_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_sellers
FROM 'C:\OlistData\olist_sellers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_geolocation
FROM 'C:\OlistData\olist_geolocation_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_category_translation
FROM 'C:\OlistData\product_category_name_translation.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

/* NOTE: if BULK INSERT throws row-parsing errors on stg_order_reviews
   (common — some review comments contain embedded newlines/quotes that
   trip up plain CSV parsing), use the Import/Export Wizard or
   SSIS Flat File Source for that one file instead — both handle quoted
   multi-line text more reliably than raw BULK INSERT. */


/* ============================================================================
   STEP 3 — STAR SCHEMA VIEWS
   ============================================================================ */

/* ----------------------------------------------------------------------
   DIM DATE — same generator pattern as the AdventureWorks project
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
   customer_unique_id identifies the actual person; customer_id is
   per-order — keep both so you can measure repeat purchases correctly.
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
FROM stg_customers;
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
FROM stg_sellers;
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
FROM stg_products p
LEFT JOIN stg_category_translation t ON p.product_category_name = t.product_category_name;
GO

/* ----------------------------------------------------------------------
   FACT ORDER ITEMS  (grain: one row per order line item)
   Core sales fact — price, freight, delivery timing.
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
FROM stg_order_items oi
JOIN stg_orders o ON oi.order_id = o.order_id;
GO

/* ----------------------------------------------------------------------
   FACT PAYMENTS  (grain: one row per payment installment record per order)
   Kept SEPARATE from FactOrderItems — an order can have multiple items
   AND multiple payment rows, so joining them directly would double-count
   payment_value across every item in the order.
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
FROM stg_order_payments op
JOIN stg_orders o ON op.order_id = o.order_id;
GO

/* ----------------------------------------------------------------------
   FACT REVIEWS  (grain: one row per review, i.e. per order)
   Also kept separate for the same fan-out reason as payments.
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
FROM stg_order_reviews r
JOIN stg_orders o ON r.order_id = o.order_id;
GO

PRINT 'Olist staging tables and star-schema views created successfully.';
