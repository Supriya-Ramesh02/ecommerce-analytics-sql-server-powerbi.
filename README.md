# Brazilian E-Commerce Analytics

## Overview

End-to-end data analytics project using the Olist Brazilian E-Commerce
dataset to analyze sales, customers, products, sellers, payments,
reviews, and delivery performance.

## Tech Stack

- SQL Server
- SQL
- Power BI
- DAX
- Star Schema
- Data Modeling

## Project Architecture

Raw CSV Data
      ↓
SQL Server
      ↓
Data Cleaning & Transformation
      ↓
Star Schema
      ↓
Business Metrics
      ↓
Power BI Dashboard

## SQL Data Model

The project uses a star-schema approach with:

### Dimensions
- DimDate
- DimCustomer
- DimSeller
- DimProduct

### Facts
- FactOrderItems
- FactPayments
- FactReviews

## Power BI Dashboard

The dashboard contains:

- Executive Summary
- Sales & Delivery
- Product & Seller
- Customer & Reviews

## Key Analysis

The project analyzes:

- Revenue
- Orders
- Average Order Value
- Delivery performance
- Late delivery rate
- Product categories
- Seller performance
- Customer behavior
- Payment methods
- Review scores

## Repository Structure

```text
SQL/
PowerBI/
screenshots/
README.md
