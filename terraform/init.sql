-- Initialize and populate the MySQL database with sample data 
-- This script is meant to be run inside the MySQL container automatically after it has been started.

CREATE DATABASE IF NOT EXISTS my_precious_bank;
USE my_precious_bank;

-- Customer PII (Target for extortion and regulations)
CREATE TABLE IF NOT EXISTS customer_profile (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    password VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    full_name VARCHAR(255) NOT NULL,
    phone_nuumber CHAR(8) NOT NULL, -- Specific for Togo number
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Business continuity (Target for Ransomware / Financial Disruption)
CREATE TABLE IF NOT EXISTS inventory_ledgers (
    item_id INT AUTO_INCREMENT PRIMARY KEY,
    product VARCHAR(50),
    stock_count INT,
    wholesale_price DECIMAL(10,2)
);

-- Apps and Infrastrcture secrets (Target for lateral movement)
CREATE TABLE IF NOT EXISTS app_configs (
    config_key VARCHAR(50),
    config_value VARCHAR(255)
);

-----------------------------
-- Sample Data Insertion
-----------------------------

-- 1. Customer PII Records (High-value targets for data exfiltration)
INSERT INTO customer_profile (password, email, full_name, phone_nuumber) VALUES
('P@ssw0rd2024!', 'koffi.mensah@preciousbank.tg', 'Koffi Mensah', '90123456'),
('TogoSecure#99', 'amina.lawson@preciousbank.tg', 'Amina Lawson', '91234567'),
('BankAdmin@2025', 'yao.adams@preciousbank.tg', 'Yao Adams', '92345678'),
('C0mpl3x!Pass', 'adjovi.ayimolou@preciousbank.tg', 'Adjovi ayimolou', '93456789'),
('V!pClient#42', 'kodjo.dosseh@preciousbank.tg', 'Kodjo Dosseh', '70123456');

-- 2. Business Continuity Assets (Inventory & Pricing)
INSERT INTO inventory_ledgers (product, stock_count, wholesale_price) VALUES
('Hardware Security Module (HSM)', 12, 14500.00),
('Core Banking Server Blade', 6, 8200.50),
('Encrypted Backup Tape LTO-9', 150, 125.00),
('Biometric Authentication Terminal', 45, 650.00),
('Out-of-Band Management Switch', 8, 2300.75);

-- 3. App Configuration Secrets (Prime targets for lateral movement)
INSERT INTO app_configs (config_key, config_value) VALUES
('JWT_SIGNING_SECRET', 'd8f9a2e4b7c1d3e5f6a8b0c2d4e6f8a0b2c4d6e8f0a2b4c6d8e0f2a4b6c8d0e2'),
('PAYMENT_GATEWAY_API_TOKEN', 'pg_live_99283748291048572019384756201928'),
('INTERNAL_BACKUP_S3_KEY', 'AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'),
('SWIFT_GATEWAY_ENDPOINT', 'https://swift-core.internal.preciousbank.tg:8443/v2/transfer'),
('DB_ENCRYPTION_MASTER_KEY', 'kms-key-tg-lome-dc1-master-vault-v1');
