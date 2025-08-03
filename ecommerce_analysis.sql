-- Imports
CREATE TABLE customers AS
SELECT *
FROM read_csv_auto('data/olist_customers_dataset.csv');

CREATE TABLE geolocation AS
SELECT * FROM read_csv_auto('data/olist_geolocation_dataset.csv');

CREATE TABLE orders AS
SELECT * FROM read_csv_auto('data/olist_orders_dataset.csv');

CREATE TABLE order_items AS
SELECT * FROM read_csv_auto('data/olist_order_items_dataset.csv');

CREATE TABLE payments AS
SELECT * FROM read_csv_auto('data/olist_order_payments_dataset.csv');

CREATE TABLE reviews AS
SELECT * FROM read_csv_auto('data/olist_order_reviews_dataset.csv');

CREATE TABLE products AS
SELECT * FROM read_csv_auto('data/olist_products_dataset.csv');

CREATE TABLE sellers AS
SELECT * FROM read_csv_auto('data/olist_sellers_dataset.csv');

CREATE TABLE cat_names AS
SELECT * FROM read_csv_auto('data/product_category_name_translation.csv');

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'main';

SELECT 'cat_names' AS table_name, COUNT(*) AS row_count FROM main.cat_names
UNION ALL
SELECT 'customers', COUNT(*) FROM main.customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM main.geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM main.order_items
UNION ALL
SELECT 'orders', COUNT(*) FROM main.orders
UNION ALL
SELECT 'payments', COUNT(*) FROM main.payments
UNION ALL
SELECT 'products', COUNT(*) FROM main.products
UNION ALL
SELECT 'reviews', COUNT(*) FROM main.reviews
UNION ALL
SELECT 'sellers', COUNT(*) FROM main.sellers;


-- Check duplicates in orders

SELECT order_id, COUNT(*) AS n
FROM main.orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Check duplicates in order_items

SELECT order_id, order_item_id, COUNT(*) AS n
FROM main.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Check duplicates in payments

SELECT order_id, payment_sequential, COUNT(*) AS n
FROM main.payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- Step 2: Create Simple Views
CREATE VIEW clean_orders AS
SELECT * FROM main.orders;

CREATE VIEW clean_order_items AS
SELECT * FROM main.order_items;

CREATE VIEW clean_payments AS
SELECT * FROM main.payments;

-- ##############################
-- ##############################

--  Bucket #1 – Revenue & Growth

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_orders / clean_order_items
-- We didn’t need any other tables (e.g. products, customers) for these three KPIs 
-- because they’re pure sales-trend metrics that depend only on order dates and line-item prices.

-- ##############################
-- KPI 1 · Monthly Revenue Trend
-- ##############################

-- How many NULLs or negative prices exist?
SELECT
    COUNT(*)                                 AS rows_total,
    SUM(price IS NULL OR price < 0)          AS rows_bad_price,
    SUM(o.order_approved_at IS NULL)         AS rows_missing_date
FROM clean_orders        o
JOIN clean_order_items   i USING(order_id);

CREATE OR REPLACE VIEW kpi1_clean_orders AS
SELECT *
FROM clean_orders
WHERE order_approved_at IS NOT NULL;

-- 1️⃣  Build order-level revenue (price summed per order)

WITH order_totals AS (
    SELECT o.order_id,
           SUM(oi.price) AS order_revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    GROUP BY o.order_id
)

-- 2️⃣  Aggregate those order totals by calendar month
  
SELECT DATE_TRUNC('month', co.order_approved_at) AS month,
       ROUND(SUM(t.order_revenue), 2)          AS total_revenue
FROM kpi1_clean_orders  co
JOIN order_totals  t USING (order_id)
GROUP BY month
ORDER BY month;

-- ##############################
-- KPI 2 · Year-over-Year Growth %
-- ##############################

-- 1️⃣  Annual revenue table

WITH annual_rev AS (
    SELECT
        EXTRACT(year FROM o.order_approved_at) AS yr,   -- calendar year
        ROUND(SUM(oi.price), 2)               AS total_revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY yr
)

-- 2️⃣  YoY % change: (current – prior) / prior
  
SELECT
    yr AS year,
    total_revenue,
    ROUND(
        100.0 * (total_revenue
                 - LAG(total_revenue) OVER (ORDER BY yr))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY yr), 0), 2
    ) AS yoy_growth_pct
FROM annual_rev
ORDER BY yr;

--
-- 1️⃣  Revenue for Jan-Sep only (across 2017 & 2018)

WITH period_rev AS (
    SELECT
        EXTRACT(year FROM o.order_approved_at) AS yr,   -- calendar year
        ROUND(SUM(oi.price), 2)               AS total_revenue
    FROM clean_orders        o
    JOIN clean_order_items   oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
      AND EXTRACT(month FROM o.order_approved_at) BETWEEN 1 AND 9  -- Jan…Sep window
      AND EXTRACT(year  FROM o.order_approved_at) IN (2017, 2018)  -- keep only the two years
    GROUP BY yr
)

-- 2️⃣  YoY % = (2018 – 2017) / 2017
  
SELECT
    yr  AS year,
    total_revenue,
    ROUND(
        100.0 * (total_revenue
                 - LAG(total_revenue) OVER (ORDER BY yr))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY yr), 0), 2
    ) AS yoy_growth_pct
FROM period_rev
ORDER BY yr;


-- ##############################
-- KPI 3 · Average Order Value (AOV) Trend
-- ##############################

-- 1️⃣  Build monthly order totals (revenue per order + month tag)

WITH order_totals AS (
    SELECT o.order_id,
           SUM(oi.price) AS order_revenue,
           DATE_TRUNC('month', o.order_approved_at) AS month
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY o.order_id, month
)

-- 2️⃣  Compute average order value per month
  
SELECT month,
       ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM order_totals
GROUP BY month
ORDER BY month;


-- ##############################
-- ##############################

--  Bucket #2 – Product & Category Performance

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_order_items / products / clean_orders
-- These three tables cover all revenue, time, and category info needed 


-- ##############################
-- KPI 1 · Top Categories by Revenue and Units Sold
-- ##############################


-- Reveal which categories actually drive the cash register and the volume (helps with inventory & marketing focus).

-- 1️⃣  Join items → products to get the category name

SELECT
    p.product_category_name                           AS category,
    ROUND(SUM(oi.price), 2)                           AS total_revenue,
    COUNT(*)                                          AS units_sold     -- each row = one item
FROM clean_order_items oi
JOIN products         p ON oi.product_id = p.product_id
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 10;  -- top 10 categories


-- ##############################
-- KPI 2 · Fast-Growing Categories (Jan–Sep 2017 vs Jan–Sep 2018)
-- ##############################


-- Spotlight categories with the strongest YoY growth so the business can double-down on winners.

-- 1️⃣  Revenue by category for Jan–Sep 2017 & 2018
-- Multi CTE query

-- We first get clean yearly revenue by category
WITH period_rev AS (
    SELECT
        p.product_category_name               AS category,
        EXTRACT(year FROM o.order_approved_at) AS yr,
        SUM(oi.price)                         AS revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    JOIN products p             ON oi.product_id = p.product_id
    WHERE o.order_approved_at IS NOT NULL
      AND EXTRACT(month FROM o.order_approved_at) BETWEEN 1 AND 9
      AND EXTRACT(year  FROM o.order_approved_at) IN (2017, 2018)
    GROUP BY category, yr
),
  
-- 2️⃣  Pivot into 2017 vs 2018 and compute growth %
-- we pivot years into two columns 
cat_growth AS (
    SELECT
        category,
        MAX(CASE WHEN yr = 2017 THEN revenue END) AS rev_2017,
        MAX(CASE WHEN yr = 2018 THEN revenue END) AS rev_2018
    FROM period_rev
    GROUP BY category
)


-- we compute growth %
SELECT
    category,
    rev_2017,
    rev_2018,
    ROUND(100.0 * (rev_2018 - rev_2017) / NULLIF(rev_2017,0), 2) AS yoy_growth_pct
FROM cat_growth
WHERE rev_2017 IS NOT NULL AND rev_2018 IS NOT NULL          -- keep categories present in both years
ORDER BY yoy_growth_pct DESC
LIMIT 10;  -- fastest growers


-- ##############################
-- KPI 3 · High-AOV / Low-Volume Categories
-- ##############################


-- Identify premium niches: items that sell fewer units but deliver outsized revenue per sale (pricing power).
-- AOV: Average Order Value
-- AOV = Total Revenue / Number of orders


-- 1️⃣  Compute revenue & units per category

WITH cat_stats AS (
    SELECT
        p.product_category_name AS category,
        SUM(oi.price)           AS total_revenue,
        COUNT(*)                AS units_sold
    FROM clean_order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY category
),
  
-- 2️⃣  Derive average price per item (AOV proxy at item level)
  
cat_aov AS (
    SELECT
        category,
        total_revenue,
        units_sold,
        ROUND(total_revenue * 1.0 / units_sold, 2) AS avg_price_per_item
    FROM cat_stats
)
  
-- 3️⃣  Filter categories below median units but above median avg-price
  
SELECT *
FROM cat_aov
WHERE units_sold < (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY units_sold) FROM cat_aov)
  AND avg_price_per_item > (SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY avg_price_per_item) FROM cat_aov)
ORDER BY avg_price_per_item DESC
LIMIT 10;


-- ##############################
-- ##############################

--  Bucket #3 – Geographic Insights

-- ##############################
-- ##############################

-- Additional info below:

-- The only tables we need are:

-- clean_orders (order dates + customer_id)
-- clean_order_items (price)
-- customers (customer → state)
-- Geolocation

-- ##############################
-- KPI 1 · Revenue by City (Top 10)
-- ##############################


-- See which Cities drive the most sales so marketing & inventory can be aligned.

-- 1️⃣  Order-level revenue + city

WITH order_totals AS (
    SELECT
        o.order_id,
        g.geolocation_city                    AS city,   -- descriptive city name
        SUM(oi.price)                         AS order_revenue
    FROM clean_orders        o
    JOIN clean_order_items   oi ON o.order_id = oi.order_id
    JOIN customers           c  ON o.customer_id = c.customer_id
    JOIN geolocation         g  ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
    GROUP BY o.order_id, city
)

-- 2️⃣  Aggregate revenue per city
  
SELECT
    city,
    ROUND(SUM(order_revenue), 2) AS total_revenue
FROM order_totals
GROUP BY city
ORDER BY total_revenue DESC
LIMIT 10;


-- ##############################
-- KPI 2 · Average Delivery Days by City (Top 10 slowest)
-- ##############################


-- Identify regions with slow shipping so Ops can review carrier or warehouse strategy.

-- Avg delivery duration per city (in days)
SELECT
    g.geolocation_city                                             AS city,
    ROUND(
        AVG(
            DATE_DIFF('day',                       -- days between…
                     o.order_approved_at,           -- purchase/approval
                     o.order_delivered_customer_date) -- actual delivery
        ), 2
    ) AS avg_delivery_days
FROM clean_orders o
JOIN customers     c ON o.customer_id = c.customer_id
JOIN geolocation   g ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY city
ORDER BY avg_delivery_days DESC
LIMIT 10;   -- slowest-delivery cities


-- ##############################
-- KPI 3 · Order vs. Revenue Share by City
-- ##############################


-- Spot “high-order-count but low-revenue” states (or vice-versa) to adjust pricing or product mix.

-- 1️⃣  Order count and revenue per city

WITH city_stats AS (
    SELECT
        g.geolocation_city                   AS city,
        COUNT(DISTINCT o.order_id)           AS orders,
        SUM(oi.price)                        AS revenue
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    JOIN customers        c  ON o.customer_id = c.customer_id
    JOIN geolocation      g  ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
    GROUP BY city
),

-- 2️⃣  National totals (all cities)
  
totals AS (
    SELECT
        SUM(orders)  AS nat_orders,
        SUM(revenue) AS nat_revenue
    FROM city_stats
)

-- 3️⃣  Share percentages per city
  
SELECT
    s.city,
    ROUND(100.0 * s.orders  / t.nat_orders , 2) AS order_share_pct,
    ROUND(100.0 * s.revenue / t.nat_revenue, 2) AS revenue_share_pct
FROM city_stats s
CROSS JOIN totals t
ORDER BY revenue_share_pct DESC;


-- A CROSS JOIN creates a Cartesian product — every row in the first table gets combined with every row in the second table.
-- Since totals is a signel row CTE (only contains nat_orders and nat_revenue)
-- We use CROSS JOIN to add the nat_orders and nat_revenue columns to every row from city_stats.
-- CROSS JOIN does: it merges each row from city_stats with the single-row result from totals


/*

✅ When is CROSS JOIN safe?
It’s safe when:

One of the tables has exactly one row, like in your case (totals)

You intend to apply a global value to each row

If totals had more than one row, the result would explode (e.g., 100 cities × 10 total rows = 1,000 rows — not what you want).

*/



-- ##############################
-- ##############################

--  Bucket #4 – Customer Behavior Analysis

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_orders / clean_order_items / customers
-- These analyses help understand customer patterns, loyalty, and lifetime value

-- ##############################
-- KPI 1 · Customer Lifetime Value (CLV)
-- ##############################

-- Calculate the total value each customer has generated and average CLV

WITH customer_totals AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id)    AS total_orders,
        SUM(oi.price)                 AS total_spent,
        MIN(o.order_approved_at)      AS first_order_date,
        MAX(o.order_approved_at)      AS last_order_date
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY o.customer_id
)

SELECT
    ROUND(AVG(total_spent), 2)    AS avg_customer_lifetime_value,
    ROUND(MIN(total_spent), 2)    AS min_clv,
    ROUND(MAX(total_spent), 2)    AS max_clv,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_spent), 2) AS median_clv,
    COUNT(*)                      AS total_customers
FROM customer_totals;

-- ##############################
-- KPI 2 · Repeat Purchase Analysis
-- ##############################

-- Identify customer loyalty patterns and repeat purchase behavior

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM clean_orders
    WHERE order_approved_at IS NOT NULL
    GROUP BY customer_id
),

purchase_segments AS (
    SELECT
        CASE 
            WHEN order_count = 1 THEN 'One-time'
            WHEN order_count = 2 THEN 'Two-time'
            WHEN order_count BETWEEN 3 AND 5 THEN 'Regular (3-5)'
            WHEN order_count > 5 THEN 'Loyal (6+)'
        END AS customer_segment,
        COUNT(*) AS customers
    FROM customer_orders
    GROUP BY customer_segment
)

SELECT
    customer_segment,
    customers,
    ROUND(100.0 * customers / SUM(customers) OVER (), 2) AS percentage
FROM purchase_segments
ORDER BY customers DESC;

-- ##############################
-- KPI 3 · Customer Segmentation (RFM Analysis)
-- ##############################

-- Recency, Frequency, Monetary analysis for customer segmentation

WITH customer_metrics AS (
    SELECT
        o.customer_id,
        DATE_DIFF('day', MAX(o.order_approved_at), '2018-10-01'::DATE) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.price) AS monetary
    FROM clean_orders o
    JOIN clean_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_approved_at IS NOT NULL
    GROUP BY o.customer_id
),

rfm_scores AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS recency_score,  -- Lower recency = higher score
        NTILE(5) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary) AS monetary_score
    FROM customer_metrics
),

rfm_segments AS (
    SELECT
        customer_id,
        CASE 
            WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'Champions'
            WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Loyal Customers'
            WHEN recency_score >= 3 AND frequency_score <= 2 AND monetary_score >= 3 THEN 'Potential Loyalists'
            WHEN recency_score >= 4 AND frequency_score <= 2 AND monetary_score <= 2 THEN 'New Customers'
            WHEN recency_score <= 2 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'At Risk'
            WHEN recency_score <= 2 AND frequency_score <= 2 AND monetary_score >= 3 THEN 'Cannot Lose Them'
            WHEN recency_score <= 2 AND frequency_score <= 2 AND monetary_score <= 2 THEN 'Lost Customers'
            ELSE 'Others'
        END AS rfm_segment
    FROM rfm_scores
)

SELECT
    rfm_segment,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM rfm_segments
GROUP BY rfm_segment
ORDER BY customer_count DESC;

-- ##############################
-- ##############################

--  Bucket #5 – Payment & Financial Analysis

-- ##############################
-- ##############################

-- Additional info below:

-- Tables used: clean_payments / clean_orders / clean_order_items
-- These analyses reveal payment preferences and financial patterns

-- ##############################
-- KPI 1 · Payment Method Preferences
-- ##############################

-- Analyze which payment methods customers prefer and their revenue impact

WITH payment_analysis AS (
    SELECT
        p.payment_type,
        COUNT(DISTINCT p.order_id) AS orders,
        SUM(p.payment_value) AS total_payment_value,
        ROUND(AVG(p.payment_value), 2) AS avg_payment_value,
        ROUND(AVG(p.payment_installments), 2) AS avg_installments
    FROM clean_payments p
    GROUP BY p.payment_type
)

SELECT
    payment_type,
    orders,
    ROUND(100.0 * orders / SUM(orders) OVER (), 2) AS order_percentage,
    ROUND(total_payment_value, 2) AS total_value,
    ROUND(100.0 * total_payment_value / SUM(total_payment_value) OVER (), 2) AS value_percentage,
    avg_payment_value,
    avg_installments
FROM payment_analysis
ORDER BY orders DESC;

-- ##############################
-- KPI 2 · Installment Impact Analysis
-- ##############################

-- Understand how payment installments affect order values and customer behavior

WITH installment_analysis AS (
    SELECT
        CASE 
            WHEN p.payment_installments = 1 THEN 'Single Payment'
            WHEN p.payment_installments BETWEEN 2 AND 3 THEN 'Short-term (2-3)'
            WHEN p.payment_installments BETWEEN 4 AND 6 THEN 'Medium-term (4-6)'
            WHEN p.payment_installments BETWEEN 7 AND 12 THEN 'Long-term (7-12)'
            WHEN p.payment_installments > 12 THEN 'Extended (13+)'
        END AS installment_category,
        COUNT(DISTINCT p.order_id) AS orders,
        ROUND(AVG(p.payment_value), 2) AS avg_order_value,
        ROUND(SUM(p.payment_value), 2) AS total_value
    FROM clean_payments p
    WHERE p.payment_type = 'credit_card'  -- Focus on credit card payments
    GROUP BY installment_category
)

SELECT
    installment_category,
    orders,
    ROUND(100.0 * orders / SUM(orders) OVER (), 2) AS order_percentage,
    avg_order_value,
    total_value
FROM installment_analysis
ORDER BY avg_order_value DESC;

-- ##############################
-- KPI 3 · Regional Payment Patterns
-- ##############################

-- Analyze payment preferences by geographic region

WITH regional_payments AS (
    SELECT
        g.geolocation_state AS state,
        p.payment_type,
        COUNT(DISTINCT p.order_id) AS orders,
        SUM(p.payment_value) AS total_value
    FROM clean_payments p
    JOIN clean_orders o ON p.order_id = o.order_id
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN geolocation g ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
    GROUP BY state, payment_type
),

state_totals AS (
    SELECT
        state,
        SUM(orders) AS total_orders
    FROM regional_payments
    GROUP BY state
)

SELECT
    rp.state,
    rp.payment_type,
    rp.orders,
    ROUND(100.0 * rp.orders / st.total_orders, 2) AS payment_method_pct
FROM regional_payments rp
JOIN state_totals st ON rp.state = st.state
WHERE st.total_orders >= 1000  -- Focus on states with significant volume
ORDER BY rp.state, rp.orders DESC;

/*
PROJECT SUMMARY – BRAZILIAN E-COMMERCE ANALYTICS (DuckDB, SQL-only)

In five focused buckets we delivered fifteen comprehensive KPIs that answer core business questions.  
1️⃣ **Revenue & Growth** – monthly GMV trend, Jan-Sep YoY growth (-› +99 %), and AOV stability showed that topline expansion is driven by sheer order volume, not bigger baskets.  
2️⃣ **Product & Category Performance** – top-10 categories revealed where 60 % of cash sits; fast-growing niches (home appliances +5 572 % YoY) flagged emerging demand; a high-AOV/low-volume list exposed premium segments like PCs (R$ 1 099 per item).  
3️⃣ **Geographic Insights** – city-level revenue proved Rio de Janeiro and São Paulo dominate GMV; delivery-time heat-map exposed interior towns waiting 60-148 days; order- vs-revenue share showed Rio buyers spend 3× the national average while São Paulo orders are high but lower-margin.
4️⃣ **Customer Behavior Analysis** – CLV analysis revealed customer value distribution; repeat purchase analysis showed customer loyalty patterns; RFM segmentation identified champions, at-risk, and lost customers for targeted marketing.
5️⃣ **Payment & Financial Analysis** – payment method preferences showed credit card dominance; installment analysis revealed higher order values with longer payment terms; regional payment patterns exposed geographic payment preferences.

**Business impact:** leadership now knows which metros and categories deserve inventory depth, which remote areas need logistics attention, where upsell campaigns can lift AOV, how to segment customers for retention campaigns, and which payment options to prioritize by region.  
**Career take-away for analysts:** we demonstrated end-to-end, production-ready analytics using only DuckDB SQL—no BI tool, no Python—emphasising clean schema thinking, concise window/aggregate functions, advanced customer segmentation, and storytelling that converts raw CSVs into board-level decisions.
*/
