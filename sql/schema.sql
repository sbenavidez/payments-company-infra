-- =============================================================================
-- Payments Company Database Schema
-- =============================================================================
-- This schema defines the core tables for the payments processing system.
-- Designed for Aurora MySQL (compatible with MySQL 8.0).
--
-- Schema Overview:
--   - merchants: Stores merchant account information
--   - payment_methods: Stores card payment data (demo environment - unencrypted)
--   - exchange_rates: Currency conversion rates
--   - transactions: Main transaction processing table
--
-- Note: This is a DEMO schema. In production, sensitive card data would be
-- tokenized and stored in a PCI-compliant vault, not in plain text.
-- =============================================================================

-- Use the payments database created by the CDK stack
USE payments;

-- =============================================================================
-- Table: merchants
-- =============================================================================
-- Stores merchant account information. Each merchant can have multiple
-- transactions processed through the payment system.
-- =============================================================================
CREATE TABLE IF NOT EXISTS merchants (
    -- Primary key: Auto-incrementing internal merchant identifier
    merchant_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    
    -- Unique external identifier for API integrations (UUID format recommended)
    external_merchant_id VARCHAR(64) NOT NULL,
    
    -- Merchant business information
    merchant_name VARCHAR(255) NOT NULL,
    
    -- Contact details
    contact_email VARCHAR(255) NOT NULL,
    contact_phone VARCHAR(32) DEFAULT NULL,
    
    -- Business address
    address_line1 VARCHAR(255) DEFAULT NULL,
    address_line2 VARCHAR(255) DEFAULT NULL,
    city VARCHAR(100) DEFAULT NULL,
    state_province VARCHAR(100) DEFAULT NULL,
    postal_code VARCHAR(20) DEFAULT NULL,
    country_code CHAR(2) DEFAULT NULL COMMENT 'ISO 3166-1 alpha-2 country code',
    
    -- Merchant status: active, suspended, terminated
    status ENUM('active', 'suspended', 'terminated') NOT NULL DEFAULT 'active',
    
    -- Audit timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (merchant_id),
    
    -- Ensure external merchant ID is unique for API lookups
    UNIQUE KEY uk_external_merchant_id (external_merchant_id),
    
    -- Index for email lookups (contact/support queries)
    INDEX idx_contact_email (contact_email),
    
    -- Index for status-based filtering (e.g., list all active merchants)
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Merchant account information for payment processing';


-- =============================================================================
-- Table: payment_methods
-- =============================================================================
-- Stores payment card data for transactions.
--
-- WARNING: This table stores card data in plain text for DEMO purposes only.
-- In a production PCI-DSS compliant environment, this data would be:
--   1. Tokenized using a payment gateway or vault service
--   2. Encrypted at rest with proper key management
--   3. Subject to strict access controls and audit logging
-- =============================================================================
CREATE TABLE IF NOT EXISTS payment_methods (
    -- Primary key: Auto-incrementing payment method identifier
    payment_method_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    
    -- Link to merchant (optional - for merchant-stored payment methods)
    merchant_id BIGINT UNSIGNED DEFAULT NULL,
    
    -- Card type: visa, mastercard, amex, discover, etc.
    card_type VARCHAR(32) NOT NULL,
    
    -- Cardholder name as printed on card
    cardholder_name VARCHAR(255) NOT NULL,
    
    -- Card number (DEMO ONLY - would be tokenized in production)
    card_number VARCHAR(19) NOT NULL COMMENT 'DEMO ONLY: Plain card number (PAN)',
    
    -- Card expiration (stored as MMYY for simplicity)
    expiration_month TINYINT UNSIGNED NOT NULL COMMENT 'Expiration month (1-12)',
    expiration_year SMALLINT UNSIGNED NOT NULL COMMENT 'Expiration year (4-digit)',
    
    -- CVV/CVC (DEMO ONLY - should NEVER be stored in production per PCI-DSS)
    cvv VARCHAR(4) DEFAULT NULL COMMENT 'DEMO ONLY: CVV should never be stored in production',
    
    -- Billing address for AVS (Address Verification System)
    billing_address_line1 VARCHAR(255) DEFAULT NULL,
    billing_address_line2 VARCHAR(255) DEFAULT NULL,
    billing_city VARCHAR(100) DEFAULT NULL,
    billing_state_province VARCHAR(100) DEFAULT NULL,
    billing_postal_code VARCHAR(20) DEFAULT NULL,
    billing_country_code CHAR(2) DEFAULT NULL COMMENT 'ISO 3166-1 alpha-2 country code',
    
    -- Payment method status
    status ENUM('active', 'expired', 'deleted') NOT NULL DEFAULT 'active',
    
    -- Audit timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (payment_method_id),
    
    -- Foreign key to merchants table
    CONSTRAINT fk_payment_methods_merchant 
        FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    
    -- Index for merchant payment method lookups
    INDEX idx_merchant_id (merchant_id),
    
    -- Index for card type analytics
    INDEX idx_card_type (card_type),
    
    -- Index for status filtering
    INDEX idx_status (status),
    
    -- Index for finding expiring cards (useful for notifications)
    INDEX idx_expiration (expiration_year, expiration_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Payment card data storage (DEMO - unencrypted for development only)';


-- =============================================================================
-- Table: exchange_rates
-- =============================================================================
-- Stores currency exchange rates for transaction currency conversion.
-- Rates are stored as the multiplier to convert from source to target currency.
-- Example: source_currency=USD, target_currency=EUR, rate=0.92 means 1 USD = 0.92 EUR
-- =============================================================================
CREATE TABLE IF NOT EXISTS exchange_rates (
    -- Primary key: Auto-incrementing rate identifier
    rate_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    
    -- Currency pair using ISO 4217 currency codes
    source_currency CHAR(3) NOT NULL COMMENT 'ISO 4217 source currency code (e.g., USD)',
    target_currency CHAR(3) NOT NULL COMMENT 'ISO 4217 target currency code (e.g., EUR)',
    
    -- Exchange rate: amount in target currency per 1 unit of source currency
    -- Using DECIMAL(20,10) for high precision in currency conversions
    exchange_rate DECIMAL(20, 10) NOT NULL COMMENT 'Rate to convert 1 unit source to target',
    
    -- Rate validity period
    -- Rates are effective from effective_from until a newer rate exists
    effective_from TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP NULL DEFAULT NULL COMMENT 'NULL means currently active rate',
    
    -- Rate source/provider for audit purposes
    rate_source VARCHAR(100) DEFAULT 'manual' COMMENT 'Source of rate (e.g., ECB, manual, api)',
    
    -- Audit timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (rate_id),
    
    -- Unique constraint: Only one active rate per currency pair at any time
    -- (enforced by application logic using effective_to IS NULL)
    UNIQUE KEY uk_active_currency_pair (source_currency, target_currency, effective_to),
    
    -- Index for looking up current rates by currency pair
    INDEX idx_currency_pair (source_currency, target_currency),
    
    -- Index for finding rates by effective date (historical lookups)
    INDEX idx_effective_from (effective_from),
    
    -- Index for finding currently active rates
    INDEX idx_active_rates (effective_to)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Currency exchange rates for transaction conversion';


-- =============================================================================
-- Table: transactions
-- =============================================================================
-- Main transaction table tracking payment processing through each step:
-- 1. pending: Initial transaction created
-- 2. authorized: Payment authorized with card issuer
-- 3. currency_converted: Currency conversion applied (if applicable)
-- 4. captured: Funds captured from cardholder
-- 5. completed: Transaction fully processed
-- 6. failed: Transaction failed at any step
-- 7. refunded: Transaction refunded to cardholder
-- 8. cancelled: Transaction cancelled before capture
-- =============================================================================
CREATE TABLE IF NOT EXISTS transactions (
    -- Primary key: Auto-incrementing internal transaction identifier
    transaction_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    
    -- External reference ID provided by merchant for their tracking
    merchant_reference_id VARCHAR(128) NOT NULL COMMENT 'Merchant-provided reference ID',
    
    -- Foreign key to merchant
    merchant_id BIGINT UNSIGNED NOT NULL,
    
    -- Foreign key to payment method used
    payment_method_id BIGINT UNSIGNED NOT NULL,
    
    -- Transaction amounts
    -- original_amount: Amount in source currency as submitted
    -- converted_amount: Amount in target currency after conversion (NULL if no conversion)
    -- final_amount: Final amount charged (in target currency if converted, else source)
    original_amount DECIMAL(19, 4) NOT NULL COMMENT 'Amount in source currency',
    converted_amount DECIMAL(19, 4) DEFAULT NULL COMMENT 'Amount after currency conversion',
    final_amount DECIMAL(19, 4) DEFAULT NULL COMMENT 'Final charged amount',
    
    -- Currency information (ISO 4217)
    source_currency CHAR(3) NOT NULL COMMENT 'Original transaction currency',
    target_currency CHAR(3) NOT NULL COMMENT 'Settlement/target currency',
    
    -- Exchange rate applied (NULL if no conversion needed)
    applied_exchange_rate DECIMAL(20, 10) DEFAULT NULL COMMENT 'Exchange rate used for conversion',
    exchange_rate_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Reference to exchange_rates table',
    
    -- Transaction status tracking the processing pipeline
    status ENUM(
        'pending',           -- Initial state, awaiting authorization
        'authorized',        -- Payment authorized with issuer
        'currency_converted', -- Currency conversion applied
        'captured',          -- Funds captured
        'completed',         -- Transaction fully processed
        'failed',            -- Failed at any step
        'refunded',          -- Full refund processed
        'partially_refunded', -- Partial refund processed
        'cancelled'          -- Cancelled before capture
    ) NOT NULL DEFAULT 'pending',
    
    -- Failure/error information
    failure_code VARCHAR(64) DEFAULT NULL COMMENT 'Error code if transaction failed',
    failure_message VARCHAR(512) DEFAULT NULL COMMENT 'Human-readable failure description',
    
    -- Authorization details from payment processor
    authorization_code VARCHAR(64) DEFAULT NULL COMMENT 'Auth code from card issuer',
    processor_transaction_id VARCHAR(128) DEFAULT NULL COMMENT 'Payment processor reference',
    
    -- Processing timestamps for each step
    authorized_at TIMESTAMP NULL DEFAULT NULL,
    currency_converted_at TIMESTAMP NULL DEFAULT NULL,
    captured_at TIMESTAMP NULL DEFAULT NULL,
    completed_at TIMESTAMP NULL DEFAULT NULL,
    failed_at TIMESTAMP NULL DEFAULT NULL,
    
    -- Standard audit timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    PRIMARY KEY (transaction_id),
    
    -- Foreign key constraints
    CONSTRAINT fk_transactions_merchant 
        FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    
    CONSTRAINT fk_transactions_payment_method 
        FOREIGN KEY (payment_method_id) REFERENCES payment_methods(payment_method_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    
    CONSTRAINT fk_transactions_exchange_rate 
        FOREIGN KEY (exchange_rate_id) REFERENCES exchange_rates(rate_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    
    -- Unique constraint: merchant_reference_id must be unique per merchant
    UNIQUE KEY uk_merchant_reference (merchant_id, merchant_reference_id),
    
    -- Index for merchant transaction lookups (most common query pattern)
    INDEX idx_merchant_id (merchant_id),
    
    -- Index for status-based queries (e.g., find all pending transactions)
    INDEX idx_status (status),
    
    -- Composite index for merchant + status queries (e.g., merchant's pending transactions)
    INDEX idx_merchant_status (merchant_id, status),
    
    -- Index for date-based queries and reporting
    INDEX idx_created_at (created_at),
    
    -- Composite index for date range queries by merchant
    INDEX idx_merchant_created (merchant_id, created_at),
    
    -- Index for currency-based analytics
    INDEX idx_currencies (source_currency, target_currency),
    
    -- Index for authorization code lookups
    INDEX idx_authorization_code (authorization_code),
    
    -- Index for processor transaction lookups
    INDEX idx_processor_transaction (processor_transaction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Main transaction table tracking payment processing lifecycle';


-- =============================================================================
-- Sample Data (Optional - for development/testing)
-- =============================================================================
-- Uncomment the following INSERT statements to populate sample data

/*
-- Sample merchant
INSERT INTO merchants (external_merchant_id, merchant_name, contact_email, contact_phone, country_code, status)
VALUES 
    ('MERCH-001-UUID', 'Acme Corporation', 'billing@acme.com', '+1-555-0100', 'US', 'active'),
    ('MERCH-002-UUID', 'Global Retail Ltd', 'payments@globalretail.co.uk', '+44-20-5550100', 'GB', 'active');

-- Sample exchange rates
INSERT INTO exchange_rates (source_currency, target_currency, exchange_rate, rate_source)
VALUES 
    ('USD', 'EUR', 0.9200000000, 'ECB'),
    ('USD', 'GBP', 0.7900000000, 'ECB'),
    ('EUR', 'USD', 1.0869565217, 'ECB'),
    ('GBP', 'USD', 1.2658227848, 'ECB'),
    ('EUR', 'GBP', 0.8586956522, 'ECB'),
    ('GBP', 'EUR', 1.1645569620, 'ECB');
*/

-- =============================================================================
-- Schema Version Tracking (Optional)
-- =============================================================================
-- You may want to add a schema_versions table to track migrations:
/*
CREATE TABLE IF NOT EXISTS schema_versions (
    version_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    version_number VARCHAR(20) NOT NULL,
    description VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (version_id),
    UNIQUE KEY uk_version (version_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Tracks applied schema migrations';

INSERT INTO schema_versions (version_number, description) VALUES ('1.0.0', 'Initial schema creation');
*/
