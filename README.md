# Brazilian E-Commerce Analytics with DuckDB

A comprehensive data analysis project exploring Brazilian e-commerce patterns using DuckDB and SQL. This project analyzes real-world e-commerce data from Olist to uncover insights about revenue trends, product performance, and geographic patterns.

## What Makes This Project Unique

While this project follows the excellent tutorial by **Anas Riad**, I've extended it with **two additional analysis buckets** that go beyond the original scope:

- **Customer Behavior Analysis**: Added comprehensive customer segmentation using RFM analysis, customer lifetime value calculations, and repeat purchase patterns to identify high-value customers and retention opportunities.

- **Payment & Financial Analysis**: Implemented deep-dive payment analytics including installment impact studies, regional payment preferences, and financial pattern recognition to optimize payment strategies.

These additions transform the project from a 3-bucket analysis (9 KPIs) to a comprehensive 5-bucket framework (15 KPIs), providing more actionable business insights for portfolio differentiation.

## Project Overview

This project demonstrates end-to-end analytics using pure SQL and DuckDB, delivering actionable business insights across five key areas:

- **Revenue & Growth Analysis** - Monthly trends, year-over-year growth, and average order value
- **Product & Category Performance** - Top categories, fast-growing segments, and premium niches
- **Geographic Insights** - City-level revenue, delivery patterns, and regional performance
- **Customer Behavior Analysis** - Customer lifetime value, repeat purchase patterns, and RFM segmentation
- **Payment & Financial Analysis** - Payment method preferences, installment impact, and regional patterns

## Prerequisites

### Install DuckDB CLI

**Windows:**
```powershell
winget install DuckDB.cli
```

**macOS:**
```bash
brew install duckdb
```

**Linux:**
```bash
curl https://install.duckdb.org | sh
```

### Dataset

Download the **Brazilian E-Commerce Public Dataset by Olist** from Kaggle:
- **Link:** https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Extract the CSV files to the `data/` folder in your project directory

## Getting Started

1. **Clone this repository:**

2. **Download and prepare the dataset:**
   - Create a `data/` folder in the project root
   - Download the Olist dataset from Kaggle
   - Extract all CSV files to the `data/` folder

3. **Launch DuckDB with web UI:**
   ```bash
   duckdb brazil_ecom.db -ui
   ```
   This will open the DuckDB web interface in your browser, and you can start working. 

## Key Findings

### Revenue & Growth
- **Monthly Revenue Trend**: Clear seasonal patterns with peak sales periods
- **YoY Growth**: +99% growth from 2017 to 2018 (Jan-Sep comparison)
- **Average Order Value**: Stable AOV indicating growth driven by order volume

### Product Performance
- **Top Categories**: Identified the 10 categories driving 60% of total revenue
- **Fast-Growing Segments**: Home appliances showing +5,572% YoY growth
- **Premium Niches**: PCs averaging R$ 1,099 per item (high-AOV, low-volume)

### Geographic Insights
- **Revenue Leaders**: Rio de Janeiro and São Paulo dominate marketplace revenue
- **Delivery Challenges**: Interior cities experiencing 60-148 day delivery times
- **Spending Patterns**: Rio buyers spend 3× national average per order

### Customer Behavior
- **Customer Lifetime Value**: Average CLV analysis and distribution patterns
- **Loyalty Segments**: 85%+ are one-time buyers, identifying retention opportunities
- **RFM Analysis**: Customer segmentation into Champions, Loyalists, At-Risk, and Lost customers

### Payment & Financial Patterns
- **Payment Preferences**: Credit card dominance with regional variations
- **Installment Impact**: Higher order values correlate with longer payment terms
- **Regional Differences**: Payment method preferences vary significantly by state

## Analysis Categories

### 1. Revenue & Growth Metrics
- Monthly revenue trends
- Year-over-year growth analysis
- Average order value (AOV) tracking

### 2. Product & Category Performance
- Top categories by revenue and units sold
- Fast-growing category identification
- High-AOV/Low-volume segment analysis

### 3. Geographic Performance
- Revenue distribution by city
- Average delivery times by location
- Order vs. revenue share analysis

### 4. Customer Behavior Analysis
- Customer Lifetime Value (CLV) calculation
- Repeat purchase rate and loyalty analysis
- RFM segmentation (Recency, Frequency, Monetary)

### 5. Payment & Financial Analysis
- Payment method preferences and distribution
- Installment impact on order values
- Regional payment pattern analysis


## Tutorial Credit

This project follows the tutorial by **Anas Riad**: "SQL + DuckDB - Data Analyst Portfolio Project E-commerce"
- **Link**: https://www.youtube.com/watch?v=JqFxZUcRImg
