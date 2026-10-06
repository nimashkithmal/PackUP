CREATE DATABASE IF NOT EXISTS packup;
USE packup;

CREATE TABLE IF NOT EXISTS users (
  id VARCHAR(64) PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  preference VARCHAR(32) NOT NULL DEFAULT 'normal',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS catalog_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  slug VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(128) NOT NULL,
  category VARCHAR(32) NOT NULL,
  qty_mode VARCHAR(32) NOT NULL,
  base_per_day FLOAT NOT NULL DEFAULT 1,
  is_safety TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  activity VARCHAR(64) NOT NULL,
  item_id INT NOT NULL,
  priority INT NOT NULL DEFAULT 70,
  FOREIGN KEY (item_id) REFERENCES catalog_items(id)
);

CREATE TABLE IF NOT EXISTS weather_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  condition_tag VARCHAR(32) NOT NULL,
  item_id INT NOT NULL,
  min_precip_prob FLOAT NULL,
  max_temp_c FLOAT NULL,
  min_temp_c FLOAT NULL,
  priority INT NOT NULL DEFAULT 75,
  FOREIGN KEY (item_id) REFERENCES catalog_items(id)
);

CREATE TABLE IF NOT EXISTS duration_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  item_id INT NOT NULL,
  extra_buffer FLOAT NOT NULL DEFAULT 0,
  FOREIGN KEY (item_id) REFERENCES catalog_items(id)
);

CREATE TABLE IF NOT EXISTS generated_lists (
  id INT AUTO_INCREMENT PRIMARY KEY,
  trip_id VARCHAR(64) NOT NULL,
  uid VARCHAR(128) NOT NULL,
  destination VARCHAR(128) NOT NULL,
  duration INT NOT NULL,
  people INT NOT NULL,
  activities_json JSON NOT NULL,
  weather_json JSON NOT NULL,
  preference VARCHAR(32) NOT NULL,
  rating INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS list_item_events (
  id INT AUTO_INCREMENT PRIMARY KEY,
  list_id INT NOT NULL,
  item_id INT NOT NULL,
  recommended TINYINT(1) NOT NULL DEFAULT 1,
  final_status VARCHAR(32) NULL,
  kept TINYINT(1) NULL,
  confidence FLOAT NULL,
  FOREIGN KEY (list_id) REFERENCES generated_lists(id),
  FOREIGN KEY (item_id) REFERENCES catalog_items(id)
);

CREATE TABLE IF NOT EXISTS ml_models (
  id INT AUTO_INCREMENT PRIMARY KEY,
  version VARCHAR(32) NOT NULL,
  metrics_json JSON NOT NULL,
  artifact_path VARCHAR(255) NOT NULL,
  trained_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trips (
  id VARCHAR(64) PRIMARY KEY,
  uid VARCHAR(128) NOT NULL,
  destination VARCHAR(128) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  people INT NOT NULL,
  activities_json TEXT NOT NULL,
  preference VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'draft',
  rating INT NULL,
  list_id INT NULL,
  weather_json TEXT NULL,
  items_json TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX ix_trips_uid (uid)
);
