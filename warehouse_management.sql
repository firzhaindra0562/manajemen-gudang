-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jul 31, 2025 at 12:59 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `warehouse_management`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `GenerateDummyData` ()   BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE max_products INT DEFAULT 1000;
    DECLARE product_start_id INT;
    
    -- Ambil ID terakhir dari tabel produk untuk memulai penomoran SKU
    SELECT COALESCE(MAX(id), 0) + 1 INTO product_start_id FROM products;

    -- Loop untuk membuat 1000 produk baru
    WHILE i <= max_products DO
        INSERT INTO products (sku, name, description, category_id, supplier_id, unit_price, minimum_stock, weight, status)
        VALUES (
            CONCAT('DUMMY-SKU-', LPAD(product_start_id + i - 1, 4, '0')),
            CONCAT('Produk Sampel ', product_start_id + i - 1),
            CONCAT('Deskripsi untuk produk sampel nomor ', product_start_id + i - 1),
            FLOOR(1 + (RAND() * 7)),  -- Kategori ID acak antara 1-7
            FLOOR(1 + (RAND() * 7)),  -- Supplier ID acak antara 1-7
            ROUND(10000 + (RAND() * 5000000)), -- Harga acak
            FLOOR(10 + (RAND() * 100)), -- Stok minimum acak
            ROUND(0.1 + (RAND() * 20), 2), -- Berat acak
            'active'
        );
        SET i = i + 1;
    END WHILE;

    -- Reset counter untuk stok
    SET i = 1;
    
    -- Loop untuk membuat data stok untuk produk yang baru dibuat
    WHILE i <= max_products DO
        INSERT INTO stock_inventory (product_id, location_id, quantity, reserved_quantity, batch_number, expiry_date, cost_per_unit)
        VALUES (
            (product_start_id + i - 1), -- ID Produk yang baru dibuat
            FLOOR(1 + (RAND() * 7)), -- Lokasi ID acak antara 1-7
            FLOOR(50 + (RAND() * 500)), -- Kuantitas acak
            0, -- Kuantitas dipesan (reserved)
            CONCAT('BATCH-', LPAD(product_start_id + i - 1, 6, '0')), -- Nomor Batch
            DATE_ADD(CURDATE(), INTERVAL FLOOR(180 + (RAND() * 1000)) DAY), -- Tanggal kadaluarsa acak
            ROUND(8000 + (RAND() * 4500000)) -- Biaya satuan acak
        );
        SET i = i + 1;
    END WHILE;

    SELECT 'SUCCESS: 1000 produk dan data stok baru berhasil dibuat.' as message;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `GenerateLowStockReport` ()  READS SQL DATA BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE prod_id INT;
    DECLARE prod_name VARCHAR(200);
    DECLARE current_stock INT;
    DECLARE min_stock INT;
    DECLARE stock_status VARCHAR(20);
    
    -- Cursor untuk produk dengan stok rendah
    DECLARE stock_cursor CURSOR FOR
        SELECT p.id, p.name, 
               COALESCE(SUM(si.quantity), 0) as current_stock,
               p.minimum_stock
        FROM products p
        LEFT JOIN stock_inventory si ON p.id = si.product_id
        WHERE p.status = 'active'
        GROUP BY p.id, p.name, p.minimum_stock
        HAVING current_stock <= p.minimum_stock;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- Temporary table untuk hasil
    DROP TEMPORARY TABLE IF EXISTS temp_low_stock;
    CREATE TEMPORARY TABLE temp_low_stock (
        product_id INT,
        product_name VARCHAR(200),
        current_stock INT,
        minimum_stock INT,
        status VARCHAR(20)
    );
    
    OPEN stock_cursor;
    
    read_loop: LOOP
        FETCH stock_cursor INTO prod_id, prod_name, current_stock, min_stock;
        
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Control flow dengan IF statement
        IF current_stock = 0 THEN
            SET stock_status = 'OUT_OF_STOCK';
        ELSEIF current_stock <= (min_stock * 0.5) THEN
            SET stock_status = 'CRITICAL_LOW';
        ELSE
            SET stock_status = 'LOW_STOCK';
        END IF;
        
        INSERT INTO temp_low_stock VALUES (prod_id, prod_name, current_stock, min_stock, stock_status);
    END LOOP;
    
    CLOSE stock_cursor;
    
    -- Return results
    SELECT * FROM temp_low_stock ORDER BY current_stock ASC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `TransferStock` (IN `p_product_id` INT, IN `p_from_location` INT, IN `p_to_location` INT, IN `p_quantity` INT, IN `p_user` VARCHAR(100), OUT `p_result_message` VARCHAR(255))  MODIFIES SQL DATA BEGIN
    DECLARE current_stock INT DEFAULT 0;
    DECLARE transfer_cost DECIMAL(10,2) DEFAULT 0;
    DECLARE batch_num VARCHAR(100);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'ERROR: Transfer failed due to database error';
    END;
    
    START TRANSACTION;
    
    -- Cek stok di lokasi asal
    SELECT COALESCE(SUM(quantity), 0), MAX(cost_per_unit), MAX(batch_number)
    INTO current_stock, transfer_cost, batch_num
    FROM stock_inventory 
    WHERE product_id = p_product_id AND location_id = p_from_location;
    
    -- Control flow dengan CASE statement
    CASE 
        WHEN current_stock < p_quantity THEN
            SET p_result_message = CONCAT('ERROR: Insufficient stock. Available: ', current_stock, ', Requested: ', p_quantity);
            ROLLBACK;
        WHEN p_quantity <= 0 THEN
            SET p_result_message = 'ERROR: Transfer quantity must be greater than 0';
            ROLLBACK;
        ELSE
            -- Update stok di lokasi asal
            UPDATE stock_inventory 
            SET quantity = quantity - p_quantity 
            WHERE product_id = p_product_id AND location_id = p_from_location;
            
            -- Insert atau update stok di lokasi tujuan
            INSERT INTO stock_inventory (product_id, location_id, quantity, cost_per_unit, batch_number)
            VALUES (p_product_id, p_to_location, p_quantity, transfer_cost, batch_num)
            ON DUPLICATE KEY UPDATE 
            quantity = quantity + p_quantity,
            cost_per_unit = transfer_cost,
            batch_number = batch_num;
            
            -- Log pergerakan stok keluar
            INSERT INTO stock_movements (product_id, location_id, movement_type, reference_type, 
                                       quantity, unit_cost, batch_number, notes, created_by)
            VALUES (p_product_id, p_from_location, 'out', 'transfer', 
                   p_quantity, transfer_cost, batch_num, 
                   CONCAT('Transfer to location ', p_to_location), p_user);
            
            -- Log pergerakan stok masuk
            INSERT INTO stock_movements (product_id, location_id, movement_type, reference_type, 
                                       quantity, unit_cost, batch_number, notes, created_by)
            VALUES (p_product_id, p_to_location, 'in', 'transfer', 
                   p_quantity, transfer_cost, batch_num, 
                   CONCAT('Transfer from location ', p_from_location), p_user);
            
            SET p_result_message = CONCAT('SUCCESS: Transferred ', p_quantity, ' units from location ', 
                                        p_from_location, ' to location ', p_to_location);
            COMMIT;
    END CASE;
END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `CalculateStockValue` (`category_id` INT, `location_id` INT) RETURNS DECIMAL(15,2) DETERMINISTIC READS SQL DATA BEGIN
    DECLARE total_value DECIMAL(15,2) DEFAULT 0.00;
    
    SELECT COALESCE(SUM(si.quantity * si.cost_per_unit), 0.00) INTO total_value
    FROM stock_inventory si
    JOIN products p ON si.product_id = p.id
    WHERE p.category_id = category_id 
    AND si.location_id = location_id
    AND p.status = 'active';
    
    RETURN total_value;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `GetTotalActiveProducts` () RETURNS INT(11) DETERMINISTIC READS SQL DATA BEGIN
    DECLARE total_products INT DEFAULT 0;
    SELECT COUNT(*) INTO total_products 
    FROM products 
    WHERE status = 'active';
    RETURN total_products;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `audit_log`
--

CREATE TABLE `audit_log` (
  `id` int(11) NOT NULL,
  `table_name` varchar(100) NOT NULL,
  `operation_type` enum('INSERT','UPDATE','DELETE') NOT NULL,
  `record_id` int(11) NOT NULL,
  `old_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_values`)),
  `new_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_values`)),
  `changed_by` varchar(100) DEFAULT NULL,
  `change_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `ip_address` varchar(45) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_log`
--

INSERT INTO `audit_log` (`id`, `table_name`, `operation_type`, `record_id`, `old_values`, `new_values`, `changed_by`, `change_date`, `ip_address`) VALUES
(1, 'products', 'UPDATE', 1, '{\"name\": \"Smartphone Samsung Galaxy A54\", \"unit_price\": 4500000.00, \"status\": \"active\", \"minimum_stock\": 10}', '{\"name\": \"Samsung Galaxy A54\", \"unit_price\": 4500000.00, \"status\": \"active\", \"minimum_stock\": 10}', 'root@localhost', '2025-07-31 00:22:26', NULL),
(2, 'order_details', 'INSERT', 10, NULL, '{\"order_id\": 6, \"product_id\": 2, \"quantity\": 10, \"unit_price\": 8500000.00, \"line_total\": 85000000.00}', 'root@localhost', '2025-07-31 02:47:37', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `categories`
--

CREATE TABLE `categories` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `categories`
--

INSERT INTO `categories` (`id`, `name`, `description`, `created_at`, `updated_at`) VALUES
(1, 'Electronics', 'Electronic devices and gadgets', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(2, 'Clothing', 'Apparel and fashion items', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(3, 'Food & Beverage', 'Food products and drinks', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(4, 'Office Supplies', 'Office and stationery items', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(5, 'Home & Garden', 'Home improvement and garden supplies', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(6, 'Sports & Recreation', 'Sports equipment and recreational items', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(7, 'Automotive', 'Vehicle parts and accessories', '2025-07-30 23:49:18', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Table structure for table `customers`
--

CREATE TABLE `customers` (
  `id` int(11) NOT NULL,
  `customer_code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `city` varchar(50) DEFAULT NULL,
  `postal_code` varchar(10) DEFAULT NULL,
  `customer_type` enum('regular','wholesale','retail') DEFAULT 'regular',
  `credit_limit` decimal(12,2) DEFAULT 0.00,
  `status` enum('active','inactive') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `customers`
--

INSERT INTO `customers` (`id`, `customer_code`, `name`, `email`, `phone`, `address`, `city`, `postal_code`, `customer_type`, `credit_limit`, `status`, `created_at`, `updated_at`) VALUES
(1, 'CUST001', 'Toko Elektronik Maju', 'maju@elektronik.com', '021-1234567', 'Jl. Raya No. 123', 'Jakarta', NULL, 'wholesale', 50000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(2, 'CUST002', 'Fashion Boutique', 'info@fashionboutique.com', '0274-234567', 'Jl. Malioboro No. 234', 'Yogyakarta', NULL, 'retail', 25000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(3, 'CUST003', 'Supermarket Fresh', 'fresh@supermarket.com', '022-345678', 'Jl. Asia Afrika No. 345', 'Bandung', NULL, 'wholesale', 75000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(4, 'CUST004', 'Office Center', 'center@office.com', '021-456789', 'Jl. Sudirman No. 456', 'Jakarta', NULL, 'regular', 30000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(5, 'CUST005', 'Home Depot', 'depot@home.com', '024-567890', 'Jl. Pemuda No. 567', 'Semarang', NULL, 'retail', 40000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(6, 'CUST006', 'Sports Kingdom', 'kingdom@sports.com', '031-678901', 'Jl. Veteran No. 678', 'Surabaya', NULL, 'regular', 20000000.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Stand-in structure for view `manager_order_view`
-- (See below for the actual view)
--
CREATE TABLE `manager_order_view` (
`id` int(11)
,`order_number` varchar(50)
,`customer_id` int(11)
,`order_date` timestamp
,`total_amount` decimal(12,2)
,`final_amount` decimal(12,2)
,`status` enum('pending','processing','shipped','delivered','cancelled')
,`created_by` varchar(100)
,`customer_name` varchar(150)
,`customer_type` enum('regular','wholesale','retail')
,`credit_limit` decimal(12,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `orders`
--

CREATE TABLE `orders` (
  `id` int(11) NOT NULL,
  `order_number` varchar(50) NOT NULL,
  `customer_id` int(11) NOT NULL,
  `order_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `total_amount` decimal(12,2) DEFAULT 0.00,
  `tax_amount` decimal(10,2) DEFAULT 0.00,
  `discount_amount` decimal(10,2) DEFAULT 0.00,
  `final_amount` decimal(12,2) DEFAULT 0.00,
  `status` enum('pending','processing','shipped','delivered','cancelled') DEFAULT 'pending',
  `notes` text DEFAULT NULL,
  `created_by` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `orders`
--

INSERT INTO `orders` (`id`, `order_number`, `customer_id`, `order_date`, `total_amount`, `tax_amount`, `discount_amount`, `final_amount`, `status`, `notes`, `created_by`) VALUES
(1, 'ORD-2024-001', 1, '2025-07-30 23:49:18', 45000000.00, 4500000.00, 0.00, 49500000.00, 'delivered', NULL, 'staff1'),
(2, 'ORD-2024-002', 2, '2025-07-30 23:49:18', 8750000.00, 875000.00, 0.00, 9625000.00, 'shipped', NULL, 'staff2'),
(3, 'ORD-2024-003', 3, '2025-07-30 23:49:18', 6200000.00, 620000.00, 0.00, 6820000.00, 'processing', NULL, 'staff1'),
(4, 'ORD-2024-004', 4, '2025-07-30 23:49:18', 12500000.00, 1250000.00, 0.00, 13750000.00, 'pending', NULL, 'staff2'),
(5, 'ORD-2024-005', 1, '2025-07-30 23:49:18', 25000000.00, 2500000.00, 0.00, 27500000.00, 'delivered', NULL, 'staff1'),
(6, 'ORD-1753930014', 1, '2025-07-31 02:47:37', 85000000.00, 8500000.00, 0.00, 93500000.00, 'pending', NULL, 'staff1');

-- --------------------------------------------------------

--
-- Table structure for table `order_details`
--

CREATE TABLE `order_details` (
  `id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `discount_percentage` decimal(5,2) DEFAULT 0.00,
  `line_total` decimal(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `order_details`
--

INSERT INTO `order_details` (`id`, `order_id`, `product_id`, `quantity`, `unit_price`, `discount_percentage`, `line_total`) VALUES
(1, 1, 1, 10, 4500000.00, 0.00, 45000000.00),
(2, 2, 4, 35, 125000.00, 0.00, 4375000.00),
(3, 2, 5, 17, 250000.00, 0.00, 4250000.00),
(4, 3, 6, 20, 150000.00, 0.00, 3000000.00),
(5, 3, 7, 24, 85000.00, 0.00, 2040000.00),
(6, 3, 3, 1, 2500000.00, 0.00, 2500000.00),
(7, 4, 8, 5, 1850000.00, 0.00, 9250000.00),
(8, 4, 9, 50, 65000.00, 0.00, 3250000.00),
(9, 5, 2, 3, 8500000.00, 0.00, 25500000.00),
(10, 6, 2, 10, 8500000.00, 0.00, 85000000.00);

--
-- Triggers `order_details`
--
DELIMITER $$
CREATE TRIGGER `after_order_detail_insert` AFTER INSERT ON `order_details` FOR EACH ROW BEGIN
    DECLARE order_total DECIMAL(12,2) DEFAULT 0;
    DECLARE tax_rate DECIMAL(5,4) DEFAULT 0.10; -- 10% tax
    
    -- Hitung ulang total order
    SELECT SUM(line_total) INTO order_total
    FROM order_details
    WHERE order_id = NEW.order_id;
    
    -- Update orders table dengan total baru
    UPDATE orders 
    SET total_amount = order_total,
        tax_amount = order_total * tax_rate,
        final_amount = order_total + (order_total * tax_rate)
    WHERE id = NEW.order_id;
    
    -- Log ke audit untuk tracking
    INSERT INTO audit_log (table_name, operation_type, record_id, new_values, changed_by)
    VALUES (
        'order_details',
        'INSERT',
        NEW.id,
        JSON_OBJECT(
            'order_id', NEW.order_id,
            'product_id', NEW.product_id,
            'quantity', NEW.quantity,
            'unit_price', NEW.unit_price,
            'line_total', NEW.line_total
        ),
        USER()
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `id` int(11) NOT NULL,
  `sku` varchar(50) NOT NULL,
  `name` varchar(200) NOT NULL,
  `description` text DEFAULT NULL,
  `category_id` int(11) NOT NULL,
  `supplier_id` int(11) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `minimum_stock` int(11) DEFAULT 10,
  `weight` decimal(8,2) DEFAULT 0.00,
  `status` enum('active','inactive','discontinued') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`id`, `sku`, `name`, `description`, `category_id`, `supplier_id`, `unit_price`, `minimum_stock`, `weight`, `status`, `created_at`, `updated_at`) VALUES
(1, 'ELK001', 'Samsung Galaxy A54', 'Smartphone Android terbaru', 1, 1, 4500000.00, 10, 0.20, 'active', '2025-07-30 23:49:18', '2025-07-31 00:22:26'),
(2, 'ELK002', 'Laptop ASUS VivoBook 15', 'Laptop untuk kerja dan gaming ringan', 1, 1, 8500000.00, 5, 1.80, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(3, 'ELK003', 'Earphone Sony WH-1000XM4', 'Earphone noise cancelling premium', 1, 1, 2500000.00, 15, 0.30, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(4, 'CLT001', 'Kaos Polo Pria', 'Kaos polo cotton combed premium', 2, 2, 125000.00, 50, 0.20, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(5, 'CLT002', 'Jeans Wanita Skinny', 'Celana jeans stretch untuk wanita', 2, 2, 250000.00, 30, 0.50, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(6, 'FNB001', 'Coffee Arabica Premium 1kg', 'Kopi arabica premium dari Aceh', 3, 3, 150000.00, 100, 1.00, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(7, 'FNB002', 'Green Tea Organic 500g', 'Teh hijau organik tanpa pestisida', 3, 3, 85000.00, 80, 0.50, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(8, 'OFF001', 'Printer Canon PIXMA G2010', 'Printer inkjet dengan tangki tinta', 4, 4, 1850000.00, 8, 5.50, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(9, 'OFF002', 'Kertas A4 Paper One 80gsm', 'Kertas fotocopy berkualitas tinggi', 4, 4, 65000.00, 200, 2.50, 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(10, 'ELC-0725-101', 'Monitor Ultrawide LG 34\"', 'Monitor 34 inch untuk produktivitas dan gaming, resolusi 3440x1440.', 1, 1, 5650000.00, 5, 7.80, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(11, 'ELC-0725-102', 'Keyboard Mekanikal Keychron K2', 'Keyboard mekanikal 75% dengan hotswap-able switch dan koneksi bluetooth.', 1, 1, 1350000.00, 10, 0.80, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(12, 'ELC-0725-103', 'Mouse Logitech MX Master 3S', 'Mouse ergonomis untuk profesional dengan silent click dan scroll wheel magspeed.', 1, 4, 1499000.00, 15, 0.14, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(13, 'CLK-0725-201', 'Kemeja Flanel Uniqlo Pria', 'Kemeja flanel lengan panjang bahan katun tebal dan lembut.', 2, 2, 499000.00, 25, 0.40, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(14, 'CLK-0725-202', 'Celana Chino Pria Slim Fit', 'Celana chino bahan katun stretch yang nyaman untuk sehari-hari.', 2, 2, 350000.00, 30, 0.60, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(15, 'FNB-0725-301', 'Madu Hutan Uray 640ml', 'Madu murni dari lebah hutan liar, tanpa proses tambahan.', 3, 3, 115000.00, 50, 0.90, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(16, 'FNB-0725-302', 'Keripik Singkong Balado 250gr', 'Keripik singkong renyah dengan bumbu balado pedas manis asli Padang.', 3, 3, 25000.00, 100, 0.30, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(17, 'HAG-0725-501', 'Air Purifier Xiaomi 4 Lite', 'Pembersih udara dengan HEPA filter, efektif untuk ruangan hingga 45m2.', 5, 5, 1250000.00, 8, 4.50, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(18, 'HAG-0725-502', 'Sprei Set Katun Jepang 180x200', 'Set sprei bahan katun jepang, halus, dingin, dan tidak luntur.', 5, 5, 320000.00, 20, 1.20, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(19, 'ATM-0725-701', 'Oli Mesin Shell Helix HX8 5W-30', 'Oli mesin fully synthetic untuk mobil bensin, kemasan 4 liter.', 7, 7, 450000.00, 40, 3.80, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(20, 'ATM-0725-702', 'Wiper Blade Bosch Aerotwin 24\"/16\"', 'Sepasang wiper blade frameless untuk visibilitas maksimal saat hujan.', 7, 7, 210000.00, 30, 0.50, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(21, 'ATM-0725-703', 'Kit Metalic Car Paste Wax 225gr', 'Wax poles mobil untuk mengembalikan kilap cat dan melindungi dari jamur.', 7, 7, 35000.00, 50, 0.30, 'active', '2025-07-31 03:49:21', '2025-07-31 03:49:21'),
(22, 'DUMMY-SKU-0022', 'Produk Sampel 22', 'Deskripsi untuk produk sampel nomor 22', 5, 3, 3588155.00, 60, 7.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(23, 'DUMMY-SKU-0023', 'Produk Sampel 23', 'Deskripsi untuk produk sampel nomor 23', 3, 3, 908940.00, 75, 14.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(24, 'DUMMY-SKU-0024', 'Produk Sampel 24', 'Deskripsi untuk produk sampel nomor 24', 5, 1, 1454717.00, 41, 14.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(25, 'DUMMY-SKU-0025', 'Produk Sampel 25', 'Deskripsi untuk produk sampel nomor 25', 5, 3, 2524692.00, 64, 4.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(26, 'DUMMY-SKU-0026', 'Produk Sampel 26', 'Deskripsi untuk produk sampel nomor 26', 4, 5, 3114535.00, 42, 15.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(27, 'DUMMY-SKU-0027', 'Produk Sampel 27', 'Deskripsi untuk produk sampel nomor 27', 6, 6, 3128626.00, 77, 9.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(28, 'DUMMY-SKU-0028', 'Produk Sampel 28', 'Deskripsi untuk produk sampel nomor 28', 4, 5, 582286.00, 63, 6.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(29, 'DUMMY-SKU-0029', 'Produk Sampel 29', 'Deskripsi untuk produk sampel nomor 29', 7, 6, 1305095.00, 93, 7.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(30, 'DUMMY-SKU-0030', 'Produk Sampel 30', 'Deskripsi untuk produk sampel nomor 30', 3, 7, 1209260.00, 62, 18.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(31, 'DUMMY-SKU-0031', 'Produk Sampel 31', 'Deskripsi untuk produk sampel nomor 31', 7, 7, 4210223.00, 53, 13.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(32, 'DUMMY-SKU-0032', 'Produk Sampel 32', 'Deskripsi untuk produk sampel nomor 32', 7, 6, 3918519.00, 86, 9.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(33, 'DUMMY-SKU-0033', 'Produk Sampel 33', 'Deskripsi untuk produk sampel nomor 33', 1, 1, 4422182.00, 41, 18.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(34, 'DUMMY-SKU-0034', 'Produk Sampel 34', 'Deskripsi untuk produk sampel nomor 34', 5, 6, 3208504.00, 103, 15.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(35, 'DUMMY-SKU-0035', 'Produk Sampel 35', 'Deskripsi untuk produk sampel nomor 35', 1, 6, 643665.00, 20, 2.91, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(36, 'DUMMY-SKU-0036', 'Produk Sampel 36', 'Deskripsi untuk produk sampel nomor 36', 3, 4, 2430011.00, 92, 13.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(37, 'DUMMY-SKU-0037', 'Produk Sampel 37', 'Deskripsi untuk produk sampel nomor 37', 7, 5, 545903.00, 90, 14.60, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(38, 'DUMMY-SKU-0038', 'Produk Sampel 38', 'Deskripsi untuk produk sampel nomor 38', 2, 6, 2403784.00, 105, 6.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(39, 'DUMMY-SKU-0039', 'Produk Sampel 39', 'Deskripsi untuk produk sampel nomor 39', 6, 5, 617091.00, 73, 16.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(40, 'DUMMY-SKU-0040', 'Produk Sampel 40', 'Deskripsi untuk produk sampel nomor 40', 2, 5, 3779866.00, 79, 3.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(41, 'DUMMY-SKU-0041', 'Produk Sampel 41', 'Deskripsi untuk produk sampel nomor 41', 7, 6, 3039483.00, 57, 10.97, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(42, 'DUMMY-SKU-0042', 'Produk Sampel 42', 'Deskripsi untuk produk sampel nomor 42', 3, 7, 2420321.00, 87, 8.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(43, 'DUMMY-SKU-0043', 'Produk Sampel 43', 'Deskripsi untuk produk sampel nomor 43', 7, 1, 4068962.00, 87, 9.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(44, 'DUMMY-SKU-0044', 'Produk Sampel 44', 'Deskripsi untuk produk sampel nomor 44', 7, 3, 1270614.00, 107, 2.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(45, 'DUMMY-SKU-0045', 'Produk Sampel 45', 'Deskripsi untuk produk sampel nomor 45', 6, 3, 3087646.00, 104, 17.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(46, 'DUMMY-SKU-0046', 'Produk Sampel 46', 'Deskripsi untuk produk sampel nomor 46', 4, 6, 3209450.00, 85, 16.92, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(47, 'DUMMY-SKU-0047', 'Produk Sampel 47', 'Deskripsi untuk produk sampel nomor 47', 7, 2, 1330482.00, 75, 9.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(48, 'DUMMY-SKU-0048', 'Produk Sampel 48', 'Deskripsi untuk produk sampel nomor 48', 3, 5, 254957.00, 36, 3.58, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(49, 'DUMMY-SKU-0049', 'Produk Sampel 49', 'Deskripsi untuk produk sampel nomor 49', 1, 7, 444531.00, 94, 19.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(50, 'DUMMY-SKU-0050', 'Produk Sampel 50', 'Deskripsi untuk produk sampel nomor 50', 2, 3, 1418688.00, 27, 0.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(51, 'DUMMY-SKU-0051', 'Produk Sampel 51', 'Deskripsi untuk produk sampel nomor 51', 5, 3, 2234501.00, 42, 5.57, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(52, 'DUMMY-SKU-0052', 'Produk Sampel 52', 'Deskripsi untuk produk sampel nomor 52', 3, 2, 3837842.00, 34, 18.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(53, 'DUMMY-SKU-0053', 'Produk Sampel 53', 'Deskripsi untuk produk sampel nomor 53', 7, 4, 523374.00, 100, 4.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(54, 'DUMMY-SKU-0054', 'Produk Sampel 54', 'Deskripsi untuk produk sampel nomor 54', 4, 4, 2071898.00, 50, 15.42, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(55, 'DUMMY-SKU-0055', 'Produk Sampel 55', 'Deskripsi untuk produk sampel nomor 55', 5, 6, 1559848.00, 13, 5.01, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(56, 'DUMMY-SKU-0056', 'Produk Sampel 56', 'Deskripsi untuk produk sampel nomor 56', 1, 7, 4995113.00, 46, 17.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(57, 'DUMMY-SKU-0057', 'Produk Sampel 57', 'Deskripsi untuk produk sampel nomor 57', 1, 1, 1439167.00, 11, 4.12, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(58, 'DUMMY-SKU-0058', 'Produk Sampel 58', 'Deskripsi untuk produk sampel nomor 58', 7, 2, 1648896.00, 99, 10.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(59, 'DUMMY-SKU-0059', 'Produk Sampel 59', 'Deskripsi untuk produk sampel nomor 59', 6, 4, 94067.00, 74, 3.62, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(60, 'DUMMY-SKU-0060', 'Produk Sampel 60', 'Deskripsi untuk produk sampel nomor 60', 7, 2, 756737.00, 25, 6.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(61, 'DUMMY-SKU-0061', 'Produk Sampel 61', 'Deskripsi untuk produk sampel nomor 61', 2, 7, 1018422.00, 24, 2.59, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(62, 'DUMMY-SKU-0062', 'Produk Sampel 62', 'Deskripsi untuk produk sampel nomor 62', 2, 4, 975304.00, 41, 0.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(63, 'DUMMY-SKU-0063', 'Produk Sampel 63', 'Deskripsi untuk produk sampel nomor 63', 1, 3, 3786707.00, 67, 11.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(64, 'DUMMY-SKU-0064', 'Produk Sampel 64', 'Deskripsi untuk produk sampel nomor 64', 2, 3, 1084785.00, 103, 0.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(65, 'DUMMY-SKU-0065', 'Produk Sampel 65', 'Deskripsi untuk produk sampel nomor 65', 3, 4, 2578490.00, 19, 19.27, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(66, 'DUMMY-SKU-0066', 'Produk Sampel 66', 'Deskripsi untuk produk sampel nomor 66', 4, 5, 2360742.00, 68, 9.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(67, 'DUMMY-SKU-0067', 'Produk Sampel 67', 'Deskripsi untuk produk sampel nomor 67', 6, 2, 3212045.00, 80, 12.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(68, 'DUMMY-SKU-0068', 'Produk Sampel 68', 'Deskripsi untuk produk sampel nomor 68', 7, 5, 1795778.00, 109, 17.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(69, 'DUMMY-SKU-0069', 'Produk Sampel 69', 'Deskripsi untuk produk sampel nomor 69', 3, 4, 935462.00, 54, 13.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(70, 'DUMMY-SKU-0070', 'Produk Sampel 70', 'Deskripsi untuk produk sampel nomor 70', 1, 2, 1122899.00, 36, 12.85, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(71, 'DUMMY-SKU-0071', 'Produk Sampel 71', 'Deskripsi untuk produk sampel nomor 71', 3, 1, 1649263.00, 41, 11.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(72, 'DUMMY-SKU-0072', 'Produk Sampel 72', 'Deskripsi untuk produk sampel nomor 72', 1, 3, 2488768.00, 64, 5.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(73, 'DUMMY-SKU-0073', 'Produk Sampel 73', 'Deskripsi untuk produk sampel nomor 73', 5, 4, 2851371.00, 41, 17.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(74, 'DUMMY-SKU-0074', 'Produk Sampel 74', 'Deskripsi untuk produk sampel nomor 74', 3, 3, 3691631.00, 62, 8.20, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(75, 'DUMMY-SKU-0075', 'Produk Sampel 75', 'Deskripsi untuk produk sampel nomor 75', 4, 1, 4963291.00, 83, 14.16, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(76, 'DUMMY-SKU-0076', 'Produk Sampel 76', 'Deskripsi untuk produk sampel nomor 76', 3, 4, 1478533.00, 23, 15.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(77, 'DUMMY-SKU-0077', 'Produk Sampel 77', 'Deskripsi untuk produk sampel nomor 77', 4, 2, 2445883.00, 92, 13.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(78, 'DUMMY-SKU-0078', 'Produk Sampel 78', 'Deskripsi untuk produk sampel nomor 78', 7, 3, 1084031.00, 106, 3.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(79, 'DUMMY-SKU-0079', 'Produk Sampel 79', 'Deskripsi untuk produk sampel nomor 79', 1, 6, 2287014.00, 19, 2.14, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(80, 'DUMMY-SKU-0080', 'Produk Sampel 80', 'Deskripsi untuk produk sampel nomor 80', 2, 6, 2616828.00, 18, 16.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(81, 'DUMMY-SKU-0081', 'Produk Sampel 81', 'Deskripsi untuk produk sampel nomor 81', 7, 2, 1766944.00, 13, 2.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(82, 'DUMMY-SKU-0082', 'Produk Sampel 82', 'Deskripsi untuk produk sampel nomor 82', 4, 1, 3043435.00, 12, 6.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(83, 'DUMMY-SKU-0083', 'Produk Sampel 83', 'Deskripsi untuk produk sampel nomor 83', 4, 3, 2389467.00, 36, 18.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(84, 'DUMMY-SKU-0084', 'Produk Sampel 84', 'Deskripsi untuk produk sampel nomor 84', 6, 2, 2599940.00, 16, 15.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(85, 'DUMMY-SKU-0085', 'Produk Sampel 85', 'Deskripsi untuk produk sampel nomor 85', 5, 6, 1961395.00, 48, 15.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(86, 'DUMMY-SKU-0086', 'Produk Sampel 86', 'Deskripsi untuk produk sampel nomor 86', 5, 5, 3962786.00, 91, 13.97, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(87, 'DUMMY-SKU-0087', 'Produk Sampel 87', 'Deskripsi untuk produk sampel nomor 87', 1, 1, 1180453.00, 107, 3.83, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(88, 'DUMMY-SKU-0088', 'Produk Sampel 88', 'Deskripsi untuk produk sampel nomor 88', 7, 4, 901992.00, 68, 8.10, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(89, 'DUMMY-SKU-0089', 'Produk Sampel 89', 'Deskripsi untuk produk sampel nomor 89', 2, 7, 1277904.00, 38, 13.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(90, 'DUMMY-SKU-0090', 'Produk Sampel 90', 'Deskripsi untuk produk sampel nomor 90', 4, 3, 3414621.00, 21, 11.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(91, 'DUMMY-SKU-0091', 'Produk Sampel 91', 'Deskripsi untuk produk sampel nomor 91', 3, 3, 3725789.00, 62, 8.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(92, 'DUMMY-SKU-0092', 'Produk Sampel 92', 'Deskripsi untuk produk sampel nomor 92', 4, 2, 3476410.00, 85, 13.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(93, 'DUMMY-SKU-0093', 'Produk Sampel 93', 'Deskripsi untuk produk sampel nomor 93', 2, 7, 28019.00, 35, 5.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(94, 'DUMMY-SKU-0094', 'Produk Sampel 94', 'Deskripsi untuk produk sampel nomor 94', 5, 1, 4250875.00, 97, 16.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(95, 'DUMMY-SKU-0095', 'Produk Sampel 95', 'Deskripsi untuk produk sampel nomor 95', 4, 2, 921427.00, 54, 14.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(96, 'DUMMY-SKU-0096', 'Produk Sampel 96', 'Deskripsi untuk produk sampel nomor 96', 2, 5, 3831961.00, 99, 3.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(97, 'DUMMY-SKU-0097', 'Produk Sampel 97', 'Deskripsi untuk produk sampel nomor 97', 2, 6, 926527.00, 60, 19.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(98, 'DUMMY-SKU-0098', 'Produk Sampel 98', 'Deskripsi untuk produk sampel nomor 98', 4, 2, 3150805.00, 68, 1.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(99, 'DUMMY-SKU-0099', 'Produk Sampel 99', 'Deskripsi untuk produk sampel nomor 99', 4, 3, 4980954.00, 19, 10.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(100, 'DUMMY-SKU-0100', 'Produk Sampel 100', 'Deskripsi untuk produk sampel nomor 100', 2, 4, 3952250.00, 62, 5.14, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(101, 'DUMMY-SKU-0101', 'Produk Sampel 101', 'Deskripsi untuk produk sampel nomor 101', 5, 5, 1887002.00, 91, 18.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(102, 'DUMMY-SKU-0102', 'Produk Sampel 102', 'Deskripsi untuk produk sampel nomor 102', 2, 3, 621844.00, 61, 4.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(103, 'DUMMY-SKU-0103', 'Produk Sampel 103', 'Deskripsi untuk produk sampel nomor 103', 5, 2, 1368266.00, 85, 19.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(104, 'DUMMY-SKU-0104', 'Produk Sampel 104', 'Deskripsi untuk produk sampel nomor 104', 5, 2, 4774139.00, 37, 10.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(105, 'DUMMY-SKU-0105', 'Produk Sampel 105', 'Deskripsi untuk produk sampel nomor 105', 6, 3, 2056627.00, 108, 14.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(106, 'DUMMY-SKU-0106', 'Produk Sampel 106', 'Deskripsi untuk produk sampel nomor 106', 5, 1, 1099800.00, 11, 8.04, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(107, 'DUMMY-SKU-0107', 'Produk Sampel 107', 'Deskripsi untuk produk sampel nomor 107', 7, 5, 134943.00, 49, 17.97, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(108, 'DUMMY-SKU-0108', 'Produk Sampel 108', 'Deskripsi untuk produk sampel nomor 108', 3, 6, 4480319.00, 31, 8.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(109, 'DUMMY-SKU-0109', 'Produk Sampel 109', 'Deskripsi untuk produk sampel nomor 109', 3, 6, 3369841.00, 13, 3.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(110, 'DUMMY-SKU-0110', 'Produk Sampel 110', 'Deskripsi untuk produk sampel nomor 110', 5, 6, 4488242.00, 28, 4.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(111, 'DUMMY-SKU-0111', 'Produk Sampel 111', 'Deskripsi untuk produk sampel nomor 111', 5, 4, 3975566.00, 40, 3.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(112, 'DUMMY-SKU-0112', 'Produk Sampel 112', 'Deskripsi untuk produk sampel nomor 112', 7, 7, 1007640.00, 16, 15.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(113, 'DUMMY-SKU-0113', 'Produk Sampel 113', 'Deskripsi untuk produk sampel nomor 113', 4, 4, 2896256.00, 67, 2.79, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(114, 'DUMMY-SKU-0114', 'Produk Sampel 114', 'Deskripsi untuk produk sampel nomor 114', 7, 3, 4811806.00, 80, 13.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(115, 'DUMMY-SKU-0115', 'Produk Sampel 115', 'Deskripsi untuk produk sampel nomor 115', 2, 7, 1313830.00, 50, 4.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(116, 'DUMMY-SKU-0116', 'Produk Sampel 116', 'Deskripsi untuk produk sampel nomor 116', 7, 1, 1320374.00, 35, 10.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(117, 'DUMMY-SKU-0117', 'Produk Sampel 117', 'Deskripsi untuk produk sampel nomor 117', 6, 3, 981906.00, 17, 16.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(118, 'DUMMY-SKU-0118', 'Produk Sampel 118', 'Deskripsi untuk produk sampel nomor 118', 6, 5, 149981.00, 13, 1.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(119, 'DUMMY-SKU-0119', 'Produk Sampel 119', 'Deskripsi untuk produk sampel nomor 119', 2, 2, 309312.00, 85, 12.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(120, 'DUMMY-SKU-0120', 'Produk Sampel 120', 'Deskripsi untuk produk sampel nomor 120', 6, 7, 2479967.00, 71, 12.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(121, 'DUMMY-SKU-0121', 'Produk Sampel 121', 'Deskripsi untuk produk sampel nomor 121', 2, 1, 479318.00, 16, 1.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(122, 'DUMMY-SKU-0122', 'Produk Sampel 122', 'Deskripsi untuk produk sampel nomor 122', 1, 1, 2051895.00, 80, 5.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(123, 'DUMMY-SKU-0123', 'Produk Sampel 123', 'Deskripsi untuk produk sampel nomor 123', 3, 5, 2761564.00, 76, 13.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(124, 'DUMMY-SKU-0124', 'Produk Sampel 124', 'Deskripsi untuk produk sampel nomor 124', 3, 7, 2387087.00, 68, 10.01, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(125, 'DUMMY-SKU-0125', 'Produk Sampel 125', 'Deskripsi untuk produk sampel nomor 125', 6, 1, 2584058.00, 26, 5.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(126, 'DUMMY-SKU-0126', 'Produk Sampel 126', 'Deskripsi untuk produk sampel nomor 126', 6, 2, 4113437.00, 46, 7.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(127, 'DUMMY-SKU-0127', 'Produk Sampel 127', 'Deskripsi untuk produk sampel nomor 127', 6, 4, 2084337.00, 62, 7.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(128, 'DUMMY-SKU-0128', 'Produk Sampel 128', 'Deskripsi untuk produk sampel nomor 128', 3, 6, 2522566.00, 42, 2.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(129, 'DUMMY-SKU-0129', 'Produk Sampel 129', 'Deskripsi untuk produk sampel nomor 129', 5, 5, 1981561.00, 16, 2.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(130, 'DUMMY-SKU-0130', 'Produk Sampel 130', 'Deskripsi untuk produk sampel nomor 130', 4, 7, 2509142.00, 64, 4.12, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(131, 'DUMMY-SKU-0131', 'Produk Sampel 131', 'Deskripsi untuk produk sampel nomor 131', 3, 3, 2154830.00, 29, 14.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(132, 'DUMMY-SKU-0132', 'Produk Sampel 132', 'Deskripsi untuk produk sampel nomor 132', 7, 3, 1342840.00, 25, 19.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(133, 'DUMMY-SKU-0133', 'Produk Sampel 133', 'Deskripsi untuk produk sampel nomor 133', 4, 4, 4755409.00, 38, 11.91, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(134, 'DUMMY-SKU-0134', 'Produk Sampel 134', 'Deskripsi untuk produk sampel nomor 134', 1, 5, 607827.00, 66, 9.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(135, 'DUMMY-SKU-0135', 'Produk Sampel 135', 'Deskripsi untuk produk sampel nomor 135', 5, 6, 3671048.00, 60, 6.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(136, 'DUMMY-SKU-0136', 'Produk Sampel 136', 'Deskripsi untuk produk sampel nomor 136', 1, 4, 4784319.00, 56, 8.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(137, 'DUMMY-SKU-0137', 'Produk Sampel 137', 'Deskripsi untuk produk sampel nomor 137', 6, 6, 2495538.00, 20, 0.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(138, 'DUMMY-SKU-0138', 'Produk Sampel 138', 'Deskripsi untuk produk sampel nomor 138', 6, 2, 1018846.00, 65, 3.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(139, 'DUMMY-SKU-0139', 'Produk Sampel 139', 'Deskripsi untuk produk sampel nomor 139', 2, 6, 4072815.00, 101, 3.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(140, 'DUMMY-SKU-0140', 'Produk Sampel 140', 'Deskripsi untuk produk sampel nomor 140', 7, 4, 2512205.00, 12, 12.60, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(141, 'DUMMY-SKU-0141', 'Produk Sampel 141', 'Deskripsi untuk produk sampel nomor 141', 1, 3, 3498309.00, 48, 16.45, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(142, 'DUMMY-SKU-0142', 'Produk Sampel 142', 'Deskripsi untuk produk sampel nomor 142', 7, 2, 2229990.00, 55, 19.40, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(143, 'DUMMY-SKU-0143', 'Produk Sampel 143', 'Deskripsi untuk produk sampel nomor 143', 4, 3, 1837039.00, 90, 18.43, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(144, 'DUMMY-SKU-0144', 'Produk Sampel 144', 'Deskripsi untuk produk sampel nomor 144', 2, 1, 435151.00, 16, 1.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(145, 'DUMMY-SKU-0145', 'Produk Sampel 145', 'Deskripsi untuk produk sampel nomor 145', 1, 2, 3137741.00, 74, 6.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(146, 'DUMMY-SKU-0146', 'Produk Sampel 146', 'Deskripsi untuk produk sampel nomor 146', 6, 5, 116990.00, 28, 17.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(147, 'DUMMY-SKU-0147', 'Produk Sampel 147', 'Deskripsi untuk produk sampel nomor 147', 6, 3, 2779986.00, 69, 6.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(148, 'DUMMY-SKU-0148', 'Produk Sampel 148', 'Deskripsi untuk produk sampel nomor 148', 6, 6, 4740362.00, 30, 4.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(149, 'DUMMY-SKU-0149', 'Produk Sampel 149', 'Deskripsi untuk produk sampel nomor 149', 3, 3, 4188148.00, 104, 4.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(150, 'DUMMY-SKU-0150', 'Produk Sampel 150', 'Deskripsi untuk produk sampel nomor 150', 2, 5, 3300003.00, 30, 1.16, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(151, 'DUMMY-SKU-0151', 'Produk Sampel 151', 'Deskripsi untuk produk sampel nomor 151', 5, 1, 2475396.00, 30, 10.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(152, 'DUMMY-SKU-0152', 'Produk Sampel 152', 'Deskripsi untuk produk sampel nomor 152', 1, 4, 1998668.00, 63, 9.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(153, 'DUMMY-SKU-0153', 'Produk Sampel 153', 'Deskripsi untuk produk sampel nomor 153', 6, 2, 4204502.00, 70, 9.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(154, 'DUMMY-SKU-0154', 'Produk Sampel 154', 'Deskripsi untuk produk sampel nomor 154', 5, 6, 3653735.00, 55, 2.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(155, 'DUMMY-SKU-0155', 'Produk Sampel 155', 'Deskripsi untuk produk sampel nomor 155', 1, 2, 255641.00, 51, 18.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(156, 'DUMMY-SKU-0156', 'Produk Sampel 156', 'Deskripsi untuk produk sampel nomor 156', 3, 7, 1902891.00, 38, 6.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(157, 'DUMMY-SKU-0157', 'Produk Sampel 157', 'Deskripsi untuk produk sampel nomor 157', 5, 4, 2334335.00, 90, 12.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(158, 'DUMMY-SKU-0158', 'Produk Sampel 158', 'Deskripsi untuk produk sampel nomor 158', 6, 1, 3431266.00, 49, 18.49, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(159, 'DUMMY-SKU-0159', 'Produk Sampel 159', 'Deskripsi untuk produk sampel nomor 159', 3, 3, 1564250.00, 72, 3.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(160, 'DUMMY-SKU-0160', 'Produk Sampel 160', 'Deskripsi untuk produk sampel nomor 160', 1, 5, 1161227.00, 23, 19.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(161, 'DUMMY-SKU-0161', 'Produk Sampel 161', 'Deskripsi untuk produk sampel nomor 161', 4, 4, 387526.00, 95, 0.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(162, 'DUMMY-SKU-0162', 'Produk Sampel 162', 'Deskripsi untuk produk sampel nomor 162', 5, 1, 2112232.00, 100, 5.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(163, 'DUMMY-SKU-0163', 'Produk Sampel 163', 'Deskripsi untuk produk sampel nomor 163', 5, 1, 4063417.00, 83, 4.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(164, 'DUMMY-SKU-0164', 'Produk Sampel 164', 'Deskripsi untuk produk sampel nomor 164', 7, 7, 2957409.00, 46, 1.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(165, 'DUMMY-SKU-0165', 'Produk Sampel 165', 'Deskripsi untuk produk sampel nomor 165', 2, 1, 2458909.00, 40, 0.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(166, 'DUMMY-SKU-0166', 'Produk Sampel 166', 'Deskripsi untuk produk sampel nomor 166', 2, 2, 930197.00, 44, 3.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(167, 'DUMMY-SKU-0167', 'Produk Sampel 167', 'Deskripsi untuk produk sampel nomor 167', 7, 6, 2215895.00, 87, 10.83, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(168, 'DUMMY-SKU-0168', 'Produk Sampel 168', 'Deskripsi untuk produk sampel nomor 168', 3, 2, 96804.00, 51, 0.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(169, 'DUMMY-SKU-0169', 'Produk Sampel 169', 'Deskripsi untuk produk sampel nomor 169', 7, 3, 2013346.00, 83, 9.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(170, 'DUMMY-SKU-0170', 'Produk Sampel 170', 'Deskripsi untuk produk sampel nomor 170', 2, 5, 3852102.00, 86, 10.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(171, 'DUMMY-SKU-0171', 'Produk Sampel 171', 'Deskripsi untuk produk sampel nomor 171', 2, 6, 297560.00, 108, 15.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(172, 'DUMMY-SKU-0172', 'Produk Sampel 172', 'Deskripsi untuk produk sampel nomor 172', 6, 7, 530876.00, 84, 8.27, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(173, 'DUMMY-SKU-0173', 'Produk Sampel 173', 'Deskripsi untuk produk sampel nomor 173', 6, 6, 3424623.00, 104, 13.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(174, 'DUMMY-SKU-0174', 'Produk Sampel 174', 'Deskripsi untuk produk sampel nomor 174', 5, 7, 5005657.00, 20, 10.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(175, 'DUMMY-SKU-0175', 'Produk Sampel 175', 'Deskripsi untuk produk sampel nomor 175', 3, 7, 3851186.00, 13, 17.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(176, 'DUMMY-SKU-0176', 'Produk Sampel 176', 'Deskripsi untuk produk sampel nomor 176', 3, 1, 1815194.00, 65, 13.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(177, 'DUMMY-SKU-0177', 'Produk Sampel 177', 'Deskripsi untuk produk sampel nomor 177', 6, 5, 4263557.00, 53, 12.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(178, 'DUMMY-SKU-0178', 'Produk Sampel 178', 'Deskripsi untuk produk sampel nomor 178', 6, 1, 344926.00, 17, 3.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(179, 'DUMMY-SKU-0179', 'Produk Sampel 179', 'Deskripsi untuk produk sampel nomor 179', 5, 6, 411229.00, 104, 9.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(180, 'DUMMY-SKU-0180', 'Produk Sampel 180', 'Deskripsi untuk produk sampel nomor 180', 4, 3, 435431.00, 47, 12.22, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(181, 'DUMMY-SKU-0181', 'Produk Sampel 181', 'Deskripsi untuk produk sampel nomor 181', 7, 6, 21755.00, 86, 16.60, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(182, 'DUMMY-SKU-0182', 'Produk Sampel 182', 'Deskripsi untuk produk sampel nomor 182', 6, 5, 3969195.00, 109, 12.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(183, 'DUMMY-SKU-0183', 'Produk Sampel 183', 'Deskripsi untuk produk sampel nomor 183', 1, 4, 1966152.00, 49, 15.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(184, 'DUMMY-SKU-0184', 'Produk Sampel 184', 'Deskripsi untuk produk sampel nomor 184', 6, 3, 3250016.00, 20, 12.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(185, 'DUMMY-SKU-0185', 'Produk Sampel 185', 'Deskripsi untuk produk sampel nomor 185', 5, 4, 3689301.00, 13, 19.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(186, 'DUMMY-SKU-0186', 'Produk Sampel 186', 'Deskripsi untuk produk sampel nomor 186', 5, 5, 4655206.00, 93, 7.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(187, 'DUMMY-SKU-0187', 'Produk Sampel 187', 'Deskripsi untuk produk sampel nomor 187', 3, 7, 2618204.00, 83, 2.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(188, 'DUMMY-SKU-0188', 'Produk Sampel 188', 'Deskripsi untuk produk sampel nomor 188', 3, 3, 3325956.00, 42, 12.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(189, 'DUMMY-SKU-0189', 'Produk Sampel 189', 'Deskripsi untuk produk sampel nomor 189', 2, 7, 2251700.00, 35, 18.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(190, 'DUMMY-SKU-0190', 'Produk Sampel 190', 'Deskripsi untuk produk sampel nomor 190', 7, 4, 739895.00, 18, 19.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(191, 'DUMMY-SKU-0191', 'Produk Sampel 191', 'Deskripsi untuk produk sampel nomor 191', 5, 4, 1872553.00, 49, 17.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(192, 'DUMMY-SKU-0192', 'Produk Sampel 192', 'Deskripsi untuk produk sampel nomor 192', 1, 6, 4910707.00, 46, 18.10, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(193, 'DUMMY-SKU-0193', 'Produk Sampel 193', 'Deskripsi untuk produk sampel nomor 193', 3, 2, 952398.00, 21, 0.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(194, 'DUMMY-SKU-0194', 'Produk Sampel 194', 'Deskripsi untuk produk sampel nomor 194', 6, 6, 4175575.00, 75, 15.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(195, 'DUMMY-SKU-0195', 'Produk Sampel 195', 'Deskripsi untuk produk sampel nomor 195', 7, 2, 230107.00, 88, 16.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(196, 'DUMMY-SKU-0196', 'Produk Sampel 196', 'Deskripsi untuk produk sampel nomor 196', 6, 1, 2433421.00, 14, 15.50, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(197, 'DUMMY-SKU-0197', 'Produk Sampel 197', 'Deskripsi untuk produk sampel nomor 197', 6, 2, 1070453.00, 34, 11.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(198, 'DUMMY-SKU-0198', 'Produk Sampel 198', 'Deskripsi untuk produk sampel nomor 198', 2, 1, 287462.00, 103, 10.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(199, 'DUMMY-SKU-0199', 'Produk Sampel 199', 'Deskripsi untuk produk sampel nomor 199', 6, 3, 1576364.00, 68, 19.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(200, 'DUMMY-SKU-0200', 'Produk Sampel 200', 'Deskripsi untuk produk sampel nomor 200', 1, 5, 2974129.00, 33, 8.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(201, 'DUMMY-SKU-0201', 'Produk Sampel 201', 'Deskripsi untuk produk sampel nomor 201', 2, 2, 1474238.00, 87, 0.12, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(202, 'DUMMY-SKU-0202', 'Produk Sampel 202', 'Deskripsi untuk produk sampel nomor 202', 5, 3, 4478336.00, 41, 17.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(203, 'DUMMY-SKU-0203', 'Produk Sampel 203', 'Deskripsi untuk produk sampel nomor 203', 4, 5, 4995281.00, 105, 15.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(204, 'DUMMY-SKU-0204', 'Produk Sampel 204', 'Deskripsi untuk produk sampel nomor 204', 1, 5, 2493648.00, 47, 8.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(205, 'DUMMY-SKU-0205', 'Produk Sampel 205', 'Deskripsi untuk produk sampel nomor 205', 7, 2, 1968070.00, 43, 9.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(206, 'DUMMY-SKU-0206', 'Produk Sampel 206', 'Deskripsi untuk produk sampel nomor 206', 3, 5, 4636521.00, 82, 16.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(207, 'DUMMY-SKU-0207', 'Produk Sampel 207', 'Deskripsi untuk produk sampel nomor 207', 1, 4, 3317429.00, 79, 9.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(208, 'DUMMY-SKU-0208', 'Produk Sampel 208', 'Deskripsi untuk produk sampel nomor 208', 3, 3, 4223507.00, 13, 13.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(209, 'DUMMY-SKU-0209', 'Produk Sampel 209', 'Deskripsi untuk produk sampel nomor 209', 1, 6, 1227700.00, 12, 8.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(210, 'DUMMY-SKU-0210', 'Produk Sampel 210', 'Deskripsi untuk produk sampel nomor 210', 7, 5, 2235046.00, 28, 11.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(211, 'DUMMY-SKU-0211', 'Produk Sampel 211', 'Deskripsi untuk produk sampel nomor 211', 3, 3, 1052366.00, 27, 4.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(212, 'DUMMY-SKU-0212', 'Produk Sampel 212', 'Deskripsi untuk produk sampel nomor 212', 5, 4, 1813797.00, 56, 4.49, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(213, 'DUMMY-SKU-0213', 'Produk Sampel 213', 'Deskripsi untuk produk sampel nomor 213', 6, 7, 2316529.00, 64, 6.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(214, 'DUMMY-SKU-0214', 'Produk Sampel 214', 'Deskripsi untuk produk sampel nomor 214', 7, 7, 3817543.00, 108, 12.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(215, 'DUMMY-SKU-0215', 'Produk Sampel 215', 'Deskripsi untuk produk sampel nomor 215', 2, 3, 648941.00, 58, 1.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(216, 'DUMMY-SKU-0216', 'Produk Sampel 216', 'Deskripsi untuk produk sampel nomor 216', 6, 7, 2215406.00, 34, 17.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(217, 'DUMMY-SKU-0217', 'Produk Sampel 217', 'Deskripsi untuk produk sampel nomor 217', 5, 5, 2720766.00, 68, 5.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(218, 'DUMMY-SKU-0218', 'Produk Sampel 218', 'Deskripsi untuk produk sampel nomor 218', 5, 4, 2476992.00, 106, 6.98, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(219, 'DUMMY-SKU-0219', 'Produk Sampel 219', 'Deskripsi untuk produk sampel nomor 219', 6, 1, 107678.00, 89, 18.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(220, 'DUMMY-SKU-0220', 'Produk Sampel 220', 'Deskripsi untuk produk sampel nomor 220', 2, 4, 4606815.00, 106, 1.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(221, 'DUMMY-SKU-0221', 'Produk Sampel 221', 'Deskripsi untuk produk sampel nomor 221', 3, 5, 1576198.00, 61, 13.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(222, 'DUMMY-SKU-0222', 'Produk Sampel 222', 'Deskripsi untuk produk sampel nomor 222', 5, 4, 3125588.00, 58, 11.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(223, 'DUMMY-SKU-0223', 'Produk Sampel 223', 'Deskripsi untuk produk sampel nomor 223', 2, 6, 4916291.00, 71, 2.50, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(224, 'DUMMY-SKU-0224', 'Produk Sampel 224', 'Deskripsi untuk produk sampel nomor 224', 6, 4, 4701517.00, 45, 19.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(225, 'DUMMY-SKU-0225', 'Produk Sampel 225', 'Deskripsi untuk produk sampel nomor 225', 6, 2, 2768954.00, 23, 0.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(226, 'DUMMY-SKU-0226', 'Produk Sampel 226', 'Deskripsi untuk produk sampel nomor 226', 5, 2, 4428468.00, 104, 1.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(227, 'DUMMY-SKU-0227', 'Produk Sampel 227', 'Deskripsi untuk produk sampel nomor 227', 4, 3, 1824414.00, 76, 4.57, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(228, 'DUMMY-SKU-0228', 'Produk Sampel 228', 'Deskripsi untuk produk sampel nomor 228', 1, 7, 2583169.00, 72, 12.20, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(229, 'DUMMY-SKU-0229', 'Produk Sampel 229', 'Deskripsi untuk produk sampel nomor 229', 1, 7, 4532317.00, 103, 19.43, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(230, 'DUMMY-SKU-0230', 'Produk Sampel 230', 'Deskripsi untuk produk sampel nomor 230', 1, 2, 148227.00, 57, 6.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(231, 'DUMMY-SKU-0231', 'Produk Sampel 231', 'Deskripsi untuk produk sampel nomor 231', 1, 5, 4971546.00, 104, 15.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(232, 'DUMMY-SKU-0232', 'Produk Sampel 232', 'Deskripsi untuk produk sampel nomor 232', 7, 4, 4700916.00, 107, 1.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(233, 'DUMMY-SKU-0233', 'Produk Sampel 233', 'Deskripsi untuk produk sampel nomor 233', 4, 1, 3455741.00, 52, 1.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(234, 'DUMMY-SKU-0234', 'Produk Sampel 234', 'Deskripsi untuk produk sampel nomor 234', 1, 2, 2585984.00, 23, 2.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(235, 'DUMMY-SKU-0235', 'Produk Sampel 235', 'Deskripsi untuk produk sampel nomor 235', 3, 1, 2271078.00, 15, 18.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(236, 'DUMMY-SKU-0236', 'Produk Sampel 236', 'Deskripsi untuk produk sampel nomor 236', 3, 7, 4136803.00, 33, 14.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(237, 'DUMMY-SKU-0237', 'Produk Sampel 237', 'Deskripsi untuk produk sampel nomor 237', 6, 7, 2602262.00, 69, 8.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(238, 'DUMMY-SKU-0238', 'Produk Sampel 238', 'Deskripsi untuk produk sampel nomor 238', 3, 5, 783428.00, 86, 7.41, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(239, 'DUMMY-SKU-0239', 'Produk Sampel 239', 'Deskripsi untuk produk sampel nomor 239', 4, 4, 896617.00, 32, 12.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(240, 'DUMMY-SKU-0240', 'Produk Sampel 240', 'Deskripsi untuk produk sampel nomor 240', 3, 6, 4827595.00, 57, 9.40, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(241, 'DUMMY-SKU-0241', 'Produk Sampel 241', 'Deskripsi untuk produk sampel nomor 241', 7, 2, 514157.00, 10, 14.13, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(242, 'DUMMY-SKU-0242', 'Produk Sampel 242', 'Deskripsi untuk produk sampel nomor 242', 4, 3, 2966777.00, 79, 13.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(243, 'DUMMY-SKU-0243', 'Produk Sampel 243', 'Deskripsi untuk produk sampel nomor 243', 3, 6, 3745475.00, 52, 17.86, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(244, 'DUMMY-SKU-0244', 'Produk Sampel 244', 'Deskripsi untuk produk sampel nomor 244', 2, 2, 1339293.00, 97, 11.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(245, 'DUMMY-SKU-0245', 'Produk Sampel 245', 'Deskripsi untuk produk sampel nomor 245', 3, 5, 2996214.00, 100, 15.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(246, 'DUMMY-SKU-0246', 'Produk Sampel 246', 'Deskripsi untuk produk sampel nomor 246', 1, 7, 1657941.00, 10, 0.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(247, 'DUMMY-SKU-0247', 'Produk Sampel 247', 'Deskripsi untuk produk sampel nomor 247', 1, 4, 72783.00, 76, 5.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(248, 'DUMMY-SKU-0248', 'Produk Sampel 248', 'Deskripsi untuk produk sampel nomor 248', 3, 1, 2165738.00, 89, 13.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(249, 'DUMMY-SKU-0249', 'Produk Sampel 249', 'Deskripsi untuk produk sampel nomor 249', 1, 2, 4467618.00, 92, 8.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(250, 'DUMMY-SKU-0250', 'Produk Sampel 250', 'Deskripsi untuk produk sampel nomor 250', 6, 2, 1152007.00, 41, 17.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(251, 'DUMMY-SKU-0251', 'Produk Sampel 251', 'Deskripsi untuk produk sampel nomor 251', 4, 6, 1269513.00, 14, 9.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(252, 'DUMMY-SKU-0252', 'Produk Sampel 252', 'Deskripsi untuk produk sampel nomor 252', 3, 7, 284557.00, 42, 8.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(253, 'DUMMY-SKU-0253', 'Produk Sampel 253', 'Deskripsi untuk produk sampel nomor 253', 2, 7, 3920224.00, 29, 13.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(254, 'DUMMY-SKU-0254', 'Produk Sampel 254', 'Deskripsi untuk produk sampel nomor 254', 5, 2, 873865.00, 32, 12.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(255, 'DUMMY-SKU-0255', 'Produk Sampel 255', 'Deskripsi untuk produk sampel nomor 255', 3, 2, 4026799.00, 49, 11.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(256, 'DUMMY-SKU-0256', 'Produk Sampel 256', 'Deskripsi untuk produk sampel nomor 256', 4, 1, 4868923.00, 58, 9.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(257, 'DUMMY-SKU-0257', 'Produk Sampel 257', 'Deskripsi untuk produk sampel nomor 257', 1, 5, 839830.00, 98, 18.40, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(258, 'DUMMY-SKU-0258', 'Produk Sampel 258', 'Deskripsi untuk produk sampel nomor 258', 7, 7, 3290696.00, 71, 2.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(259, 'DUMMY-SKU-0259', 'Produk Sampel 259', 'Deskripsi untuk produk sampel nomor 259', 6, 4, 2387832.00, 76, 18.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(260, 'DUMMY-SKU-0260', 'Produk Sampel 260', 'Deskripsi untuk produk sampel nomor 260', 4, 7, 102634.00, 43, 12.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(261, 'DUMMY-SKU-0261', 'Produk Sampel 261', 'Deskripsi untuk produk sampel nomor 261', 1, 3, 3832763.00, 79, 3.45, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(262, 'DUMMY-SKU-0262', 'Produk Sampel 262', 'Deskripsi untuk produk sampel nomor 262', 6, 3, 1075681.00, 26, 4.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(263, 'DUMMY-SKU-0263', 'Produk Sampel 263', 'Deskripsi untuk produk sampel nomor 263', 4, 1, 2958661.00, 93, 8.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(264, 'DUMMY-SKU-0264', 'Produk Sampel 264', 'Deskripsi untuk produk sampel nomor 264', 4, 4, 324145.00, 77, 3.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(265, 'DUMMY-SKU-0265', 'Produk Sampel 265', 'Deskripsi untuk produk sampel nomor 265', 7, 6, 1849490.00, 56, 4.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(266, 'DUMMY-SKU-0266', 'Produk Sampel 266', 'Deskripsi untuk produk sampel nomor 266', 5, 5, 1920858.00, 99, 6.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(267, 'DUMMY-SKU-0267', 'Produk Sampel 267', 'Deskripsi untuk produk sampel nomor 267', 7, 5, 1530287.00, 79, 11.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(268, 'DUMMY-SKU-0268', 'Produk Sampel 268', 'Deskripsi untuk produk sampel nomor 268', 6, 7, 3094647.00, 30, 3.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(269, 'DUMMY-SKU-0269', 'Produk Sampel 269', 'Deskripsi untuk produk sampel nomor 269', 2, 3, 434318.00, 59, 5.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(270, 'DUMMY-SKU-0270', 'Produk Sampel 270', 'Deskripsi untuk produk sampel nomor 270', 6, 7, 1310818.00, 74, 8.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(271, 'DUMMY-SKU-0271', 'Produk Sampel 271', 'Deskripsi untuk produk sampel nomor 271', 2, 6, 606776.00, 45, 8.60, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(272, 'DUMMY-SKU-0272', 'Produk Sampel 272', 'Deskripsi untuk produk sampel nomor 272', 1, 7, 4156013.00, 25, 5.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(273, 'DUMMY-SKU-0273', 'Produk Sampel 273', 'Deskripsi untuk produk sampel nomor 273', 7, 4, 362610.00, 85, 11.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(274, 'DUMMY-SKU-0274', 'Produk Sampel 274', 'Deskripsi untuk produk sampel nomor 274', 4, 1, 2629378.00, 62, 1.45, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(275, 'DUMMY-SKU-0275', 'Produk Sampel 275', 'Deskripsi untuk produk sampel nomor 275', 6, 4, 2907964.00, 29, 4.59, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(276, 'DUMMY-SKU-0276', 'Produk Sampel 276', 'Deskripsi untuk produk sampel nomor 276', 4, 1, 2998992.00, 95, 9.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(277, 'DUMMY-SKU-0277', 'Produk Sampel 277', 'Deskripsi untuk produk sampel nomor 277', 6, 4, 4567786.00, 33, 8.41, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(278, 'DUMMY-SKU-0278', 'Produk Sampel 278', 'Deskripsi untuk produk sampel nomor 278', 3, 5, 1419119.00, 44, 17.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(279, 'DUMMY-SKU-0279', 'Produk Sampel 279', 'Deskripsi untuk produk sampel nomor 279', 3, 1, 919354.00, 90, 9.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(280, 'DUMMY-SKU-0280', 'Produk Sampel 280', 'Deskripsi untuk produk sampel nomor 280', 1, 4, 3891628.00, 31, 14.83, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(281, 'DUMMY-SKU-0281', 'Produk Sampel 281', 'Deskripsi untuk produk sampel nomor 281', 1, 1, 4438205.00, 52, 9.04, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(282, 'DUMMY-SKU-0282', 'Produk Sampel 282', 'Deskripsi untuk produk sampel nomor 282', 7, 4, 3376907.00, 91, 1.10, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(283, 'DUMMY-SKU-0283', 'Produk Sampel 283', 'Deskripsi untuk produk sampel nomor 283', 6, 7, 144028.00, 56, 4.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(284, 'DUMMY-SKU-0284', 'Produk Sampel 284', 'Deskripsi untuk produk sampel nomor 284', 6, 2, 4543415.00, 86, 1.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(285, 'DUMMY-SKU-0285', 'Produk Sampel 285', 'Deskripsi untuk produk sampel nomor 285', 1, 4, 4229016.00, 95, 15.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(286, 'DUMMY-SKU-0286', 'Produk Sampel 286', 'Deskripsi untuk produk sampel nomor 286', 2, 6, 1438206.00, 17, 10.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(287, 'DUMMY-SKU-0287', 'Produk Sampel 287', 'Deskripsi untuk produk sampel nomor 287', 3, 4, 1392806.00, 96, 9.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(288, 'DUMMY-SKU-0288', 'Produk Sampel 288', 'Deskripsi untuk produk sampel nomor 288', 6, 5, 2594691.00, 92, 11.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(289, 'DUMMY-SKU-0289', 'Produk Sampel 289', 'Deskripsi untuk produk sampel nomor 289', 4, 4, 1407910.00, 90, 3.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(290, 'DUMMY-SKU-0290', 'Produk Sampel 290', 'Deskripsi untuk produk sampel nomor 290', 4, 6, 3847269.00, 42, 6.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23');
INSERT INTO `products` (`id`, `sku`, `name`, `description`, `category_id`, `supplier_id`, `unit_price`, `minimum_stock`, `weight`, `status`, `created_at`, `updated_at`) VALUES
(291, 'DUMMY-SKU-0291', 'Produk Sampel 291', 'Deskripsi untuk produk sampel nomor 291', 5, 2, 290272.00, 81, 7.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(292, 'DUMMY-SKU-0292', 'Produk Sampel 292', 'Deskripsi untuk produk sampel nomor 292', 6, 7, 954711.00, 25, 4.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(293, 'DUMMY-SKU-0293', 'Produk Sampel 293', 'Deskripsi untuk produk sampel nomor 293', 4, 2, 352719.00, 101, 7.12, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(294, 'DUMMY-SKU-0294', 'Produk Sampel 294', 'Deskripsi untuk produk sampel nomor 294', 1, 1, 956371.00, 89, 8.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(295, 'DUMMY-SKU-0295', 'Produk Sampel 295', 'Deskripsi untuk produk sampel nomor 295', 5, 1, 2626544.00, 40, 18.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(296, 'DUMMY-SKU-0296', 'Produk Sampel 296', 'Deskripsi untuk produk sampel nomor 296', 6, 1, 4444314.00, 41, 18.85, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(297, 'DUMMY-SKU-0297', 'Produk Sampel 297', 'Deskripsi untuk produk sampel nomor 297', 6, 6, 4802671.00, 40, 13.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(298, 'DUMMY-SKU-0298', 'Produk Sampel 298', 'Deskripsi untuk produk sampel nomor 298', 3, 7, 1661514.00, 108, 18.43, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(299, 'DUMMY-SKU-0299', 'Produk Sampel 299', 'Deskripsi untuk produk sampel nomor 299', 5, 4, 1373714.00, 15, 9.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(300, 'DUMMY-SKU-0300', 'Produk Sampel 300', 'Deskripsi untuk produk sampel nomor 300', 1, 1, 170782.00, 109, 18.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(301, 'DUMMY-SKU-0301', 'Produk Sampel 301', 'Deskripsi untuk produk sampel nomor 301', 4, 6, 780557.00, 71, 12.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(302, 'DUMMY-SKU-0302', 'Produk Sampel 302', 'Deskripsi untuk produk sampel nomor 302', 2, 7, 2512091.00, 61, 1.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(303, 'DUMMY-SKU-0303', 'Produk Sampel 303', 'Deskripsi untuk produk sampel nomor 303', 7, 1, 3348928.00, 29, 19.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(304, 'DUMMY-SKU-0304', 'Produk Sampel 304', 'Deskripsi untuk produk sampel nomor 304', 2, 2, 1921087.00, 39, 6.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(305, 'DUMMY-SKU-0305', 'Produk Sampel 305', 'Deskripsi untuk produk sampel nomor 305', 5, 4, 2503807.00, 105, 5.27, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(306, 'DUMMY-SKU-0306', 'Produk Sampel 306', 'Deskripsi untuk produk sampel nomor 306', 4, 3, 3981691.00, 80, 2.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(307, 'DUMMY-SKU-0307', 'Produk Sampel 307', 'Deskripsi untuk produk sampel nomor 307', 4, 4, 2258689.00, 105, 8.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(308, 'DUMMY-SKU-0308', 'Produk Sampel 308', 'Deskripsi untuk produk sampel nomor 308', 3, 2, 1705521.00, 102, 12.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(309, 'DUMMY-SKU-0309', 'Produk Sampel 309', 'Deskripsi untuk produk sampel nomor 309', 3, 6, 4472032.00, 23, 20.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(310, 'DUMMY-SKU-0310', 'Produk Sampel 310', 'Deskripsi untuk produk sampel nomor 310', 5, 7, 4495632.00, 79, 15.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(311, 'DUMMY-SKU-0311', 'Produk Sampel 311', 'Deskripsi untuk produk sampel nomor 311', 6, 6, 2044371.00, 80, 6.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(312, 'DUMMY-SKU-0312', 'Produk Sampel 312', 'Deskripsi untuk produk sampel nomor 312', 4, 3, 699191.00, 90, 11.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(313, 'DUMMY-SKU-0313', 'Produk Sampel 313', 'Deskripsi untuk produk sampel nomor 313', 4, 1, 2214277.00, 23, 6.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(314, 'DUMMY-SKU-0314', 'Produk Sampel 314', 'Deskripsi untuk produk sampel nomor 314', 2, 3, 3845577.00, 100, 4.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(315, 'DUMMY-SKU-0315', 'Produk Sampel 315', 'Deskripsi untuk produk sampel nomor 315', 4, 4, 1846817.00, 30, 18.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(316, 'DUMMY-SKU-0316', 'Produk Sampel 316', 'Deskripsi untuk produk sampel nomor 316', 1, 4, 2269743.00, 76, 19.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(317, 'DUMMY-SKU-0317', 'Produk Sampel 317', 'Deskripsi untuk produk sampel nomor 317', 6, 2, 1784454.00, 40, 9.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(318, 'DUMMY-SKU-0318', 'Produk Sampel 318', 'Deskripsi untuk produk sampel nomor 318', 4, 1, 3212495.00, 22, 14.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(319, 'DUMMY-SKU-0319', 'Produk Sampel 319', 'Deskripsi untuk produk sampel nomor 319', 1, 5, 2498095.00, 84, 4.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(320, 'DUMMY-SKU-0320', 'Produk Sampel 320', 'Deskripsi untuk produk sampel nomor 320', 6, 5, 1743470.00, 10, 20.10, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(321, 'DUMMY-SKU-0321', 'Produk Sampel 321', 'Deskripsi untuk produk sampel nomor 321', 7, 7, 2271871.00, 73, 16.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(322, 'DUMMY-SKU-0322', 'Produk Sampel 322', 'Deskripsi untuk produk sampel nomor 322', 2, 4, 37202.00, 57, 6.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(323, 'DUMMY-SKU-0323', 'Produk Sampel 323', 'Deskripsi untuk produk sampel nomor 323', 2, 3, 498901.00, 42, 6.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(324, 'DUMMY-SKU-0324', 'Produk Sampel 324', 'Deskripsi untuk produk sampel nomor 324', 5, 3, 4528450.00, 46, 2.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(325, 'DUMMY-SKU-0325', 'Produk Sampel 325', 'Deskripsi untuk produk sampel nomor 325', 3, 5, 921752.00, 99, 18.97, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(326, 'DUMMY-SKU-0326', 'Produk Sampel 326', 'Deskripsi untuk produk sampel nomor 326', 1, 3, 1860703.00, 108, 16.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(327, 'DUMMY-SKU-0327', 'Produk Sampel 327', 'Deskripsi untuk produk sampel nomor 327', 1, 2, 3241885.00, 70, 1.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(328, 'DUMMY-SKU-0328', 'Produk Sampel 328', 'Deskripsi untuk produk sampel nomor 328', 5, 7, 2319882.00, 80, 2.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(329, 'DUMMY-SKU-0329', 'Produk Sampel 329', 'Deskripsi untuk produk sampel nomor 329', 4, 3, 1738350.00, 60, 10.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(330, 'DUMMY-SKU-0330', 'Produk Sampel 330', 'Deskripsi untuk produk sampel nomor 330', 1, 4, 3025009.00, 53, 7.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(331, 'DUMMY-SKU-0331', 'Produk Sampel 331', 'Deskripsi untuk produk sampel nomor 331', 4, 5, 2158887.00, 41, 5.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(332, 'DUMMY-SKU-0332', 'Produk Sampel 332', 'Deskripsi untuk produk sampel nomor 332', 3, 1, 1972000.00, 74, 1.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(333, 'DUMMY-SKU-0333', 'Produk Sampel 333', 'Deskripsi untuk produk sampel nomor 333', 3, 4, 1779856.00, 47, 16.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(334, 'DUMMY-SKU-0334', 'Produk Sampel 334', 'Deskripsi untuk produk sampel nomor 334', 7, 1, 3781680.00, 59, 4.62, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(335, 'DUMMY-SKU-0335', 'Produk Sampel 335', 'Deskripsi untuk produk sampel nomor 335', 5, 4, 3163343.00, 72, 5.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(336, 'DUMMY-SKU-0336', 'Produk Sampel 336', 'Deskripsi untuk produk sampel nomor 336', 3, 7, 4672962.00, 77, 12.14, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(337, 'DUMMY-SKU-0337', 'Produk Sampel 337', 'Deskripsi untuk produk sampel nomor 337', 7, 1, 1616163.00, 56, 7.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(338, 'DUMMY-SKU-0338', 'Produk Sampel 338', 'Deskripsi untuk produk sampel nomor 338', 4, 1, 1001226.00, 77, 15.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(339, 'DUMMY-SKU-0339', 'Produk Sampel 339', 'Deskripsi untuk produk sampel nomor 339', 7, 2, 1771602.00, 19, 8.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(340, 'DUMMY-SKU-0340', 'Produk Sampel 340', 'Deskripsi untuk produk sampel nomor 340', 7, 1, 2505813.00, 54, 14.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(341, 'DUMMY-SKU-0341', 'Produk Sampel 341', 'Deskripsi untuk produk sampel nomor 341', 3, 3, 3265297.00, 42, 13.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(342, 'DUMMY-SKU-0342', 'Produk Sampel 342', 'Deskripsi untuk produk sampel nomor 342', 4, 3, 90684.00, 32, 1.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(343, 'DUMMY-SKU-0343', 'Produk Sampel 343', 'Deskripsi untuk produk sampel nomor 343', 5, 7, 2981789.00, 41, 16.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(344, 'DUMMY-SKU-0344', 'Produk Sampel 344', 'Deskripsi untuk produk sampel nomor 344', 1, 1, 3792150.00, 87, 12.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(345, 'DUMMY-SKU-0345', 'Produk Sampel 345', 'Deskripsi untuk produk sampel nomor 345', 5, 5, 1536388.00, 58, 10.31, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(346, 'DUMMY-SKU-0346', 'Produk Sampel 346', 'Deskripsi untuk produk sampel nomor 346', 1, 7, 2369747.00, 60, 2.01, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(347, 'DUMMY-SKU-0347', 'Produk Sampel 347', 'Deskripsi untuk produk sampel nomor 347', 7, 5, 4725139.00, 10, 3.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(348, 'DUMMY-SKU-0348', 'Produk Sampel 348', 'Deskripsi untuk produk sampel nomor 348', 6, 6, 1422109.00, 20, 13.16, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(349, 'DUMMY-SKU-0349', 'Produk Sampel 349', 'Deskripsi untuk produk sampel nomor 349', 7, 7, 2091743.00, 59, 4.79, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(350, 'DUMMY-SKU-0350', 'Produk Sampel 350', 'Deskripsi untuk produk sampel nomor 350', 5, 5, 2437989.00, 40, 1.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(351, 'DUMMY-SKU-0351', 'Produk Sampel 351', 'Deskripsi untuk produk sampel nomor 351', 4, 3, 429919.00, 53, 18.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(352, 'DUMMY-SKU-0352', 'Produk Sampel 352', 'Deskripsi untuk produk sampel nomor 352', 3, 6, 4389354.00, 20, 18.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(353, 'DUMMY-SKU-0353', 'Produk Sampel 353', 'Deskripsi untuk produk sampel nomor 353', 2, 2, 2516835.00, 97, 17.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(354, 'DUMMY-SKU-0354', 'Produk Sampel 354', 'Deskripsi untuk produk sampel nomor 354', 6, 3, 3408424.00, 21, 10.67, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(355, 'DUMMY-SKU-0355', 'Produk Sampel 355', 'Deskripsi untuk produk sampel nomor 355', 3, 7, 3525312.00, 85, 13.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(356, 'DUMMY-SKU-0356', 'Produk Sampel 356', 'Deskripsi untuk produk sampel nomor 356', 7, 7, 4278511.00, 49, 8.16, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(357, 'DUMMY-SKU-0357', 'Produk Sampel 357', 'Deskripsi untuk produk sampel nomor 357', 6, 7, 1843775.00, 100, 8.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(358, 'DUMMY-SKU-0358', 'Produk Sampel 358', 'Deskripsi untuk produk sampel nomor 358', 4, 7, 2580124.00, 73, 13.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(359, 'DUMMY-SKU-0359', 'Produk Sampel 359', 'Deskripsi untuk produk sampel nomor 359', 3, 6, 335680.00, 94, 0.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(360, 'DUMMY-SKU-0360', 'Produk Sampel 360', 'Deskripsi untuk produk sampel nomor 360', 4, 4, 848189.00, 31, 11.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(361, 'DUMMY-SKU-0361', 'Produk Sampel 361', 'Deskripsi untuk produk sampel nomor 361', 2, 3, 2199117.00, 101, 4.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(362, 'DUMMY-SKU-0362', 'Produk Sampel 362', 'Deskripsi untuk produk sampel nomor 362', 4, 5, 277043.00, 25, 12.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(363, 'DUMMY-SKU-0363', 'Produk Sampel 363', 'Deskripsi untuk produk sampel nomor 363', 5, 4, 1943986.00, 58, 5.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(364, 'DUMMY-SKU-0364', 'Produk Sampel 364', 'Deskripsi untuk produk sampel nomor 364', 7, 7, 2747918.00, 20, 18.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(365, 'DUMMY-SKU-0365', 'Produk Sampel 365', 'Deskripsi untuk produk sampel nomor 365', 2, 2, 3480844.00, 80, 9.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(366, 'DUMMY-SKU-0366', 'Produk Sampel 366', 'Deskripsi untuk produk sampel nomor 366', 1, 2, 4190848.00, 57, 17.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(367, 'DUMMY-SKU-0367', 'Produk Sampel 367', 'Deskripsi untuk produk sampel nomor 367', 6, 5, 3345194.00, 52, 2.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(368, 'DUMMY-SKU-0368', 'Produk Sampel 368', 'Deskripsi untuk produk sampel nomor 368', 3, 5, 3475325.00, 83, 12.04, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(369, 'DUMMY-SKU-0369', 'Produk Sampel 369', 'Deskripsi untuk produk sampel nomor 369', 6, 1, 912684.00, 69, 8.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(370, 'DUMMY-SKU-0370', 'Produk Sampel 370', 'Deskripsi untuk produk sampel nomor 370', 3, 3, 4394965.00, 37, 14.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(371, 'DUMMY-SKU-0371', 'Produk Sampel 371', 'Deskripsi untuk produk sampel nomor 371', 6, 6, 3480995.00, 12, 0.57, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(372, 'DUMMY-SKU-0372', 'Produk Sampel 372', 'Deskripsi untuk produk sampel nomor 372', 1, 2, 4181554.00, 67, 7.42, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(373, 'DUMMY-SKU-0373', 'Produk Sampel 373', 'Deskripsi untuk produk sampel nomor 373', 1, 4, 4600695.00, 34, 9.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(374, 'DUMMY-SKU-0374', 'Produk Sampel 374', 'Deskripsi untuk produk sampel nomor 374', 4, 4, 2597674.00, 36, 15.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(375, 'DUMMY-SKU-0375', 'Produk Sampel 375', 'Deskripsi untuk produk sampel nomor 375', 1, 7, 1289995.00, 76, 11.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(376, 'DUMMY-SKU-0376', 'Produk Sampel 376', 'Deskripsi untuk produk sampel nomor 376', 6, 4, 4198177.00, 88, 8.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(377, 'DUMMY-SKU-0377', 'Produk Sampel 377', 'Deskripsi untuk produk sampel nomor 377', 5, 2, 1531881.00, 77, 9.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(378, 'DUMMY-SKU-0378', 'Produk Sampel 378', 'Deskripsi untuk produk sampel nomor 378', 2, 6, 2058019.00, 67, 13.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(379, 'DUMMY-SKU-0379', 'Produk Sampel 379', 'Deskripsi untuk produk sampel nomor 379', 5, 1, 1020497.00, 10, 8.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(380, 'DUMMY-SKU-0380', 'Produk Sampel 380', 'Deskripsi untuk produk sampel nomor 380', 1, 3, 2824365.00, 72, 9.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(381, 'DUMMY-SKU-0381', 'Produk Sampel 381', 'Deskripsi untuk produk sampel nomor 381', 3, 4, 648390.00, 42, 4.45, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(382, 'DUMMY-SKU-0382', 'Produk Sampel 382', 'Deskripsi untuk produk sampel nomor 382', 1, 7, 2745257.00, 87, 4.97, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(383, 'DUMMY-SKU-0383', 'Produk Sampel 383', 'Deskripsi untuk produk sampel nomor 383', 7, 5, 4385708.00, 35, 12.85, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(384, 'DUMMY-SKU-0384', 'Produk Sampel 384', 'Deskripsi untuk produk sampel nomor 384', 4, 2, 4511355.00, 88, 4.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(385, 'DUMMY-SKU-0385', 'Produk Sampel 385', 'Deskripsi untuk produk sampel nomor 385', 6, 3, 1211897.00, 30, 6.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(386, 'DUMMY-SKU-0386', 'Produk Sampel 386', 'Deskripsi untuk produk sampel nomor 386', 7, 6, 3978500.00, 92, 14.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(387, 'DUMMY-SKU-0387', 'Produk Sampel 387', 'Deskripsi untuk produk sampel nomor 387', 1, 4, 1486484.00, 94, 6.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(388, 'DUMMY-SKU-0388', 'Produk Sampel 388', 'Deskripsi untuk produk sampel nomor 388', 2, 6, 3479319.00, 103, 12.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(389, 'DUMMY-SKU-0389', 'Produk Sampel 389', 'Deskripsi untuk produk sampel nomor 389', 2, 4, 3469465.00, 105, 14.22, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(390, 'DUMMY-SKU-0390', 'Produk Sampel 390', 'Deskripsi untuk produk sampel nomor 390', 5, 2, 4676530.00, 21, 15.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(391, 'DUMMY-SKU-0391', 'Produk Sampel 391', 'Deskripsi untuk produk sampel nomor 391', 5, 5, 2491612.00, 58, 19.16, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(392, 'DUMMY-SKU-0392', 'Produk Sampel 392', 'Deskripsi untuk produk sampel nomor 392', 3, 5, 1421139.00, 60, 13.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(393, 'DUMMY-SKU-0393', 'Produk Sampel 393', 'Deskripsi untuk produk sampel nomor 393', 6, 2, 3408573.00, 75, 4.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(394, 'DUMMY-SKU-0394', 'Produk Sampel 394', 'Deskripsi untuk produk sampel nomor 394', 2, 3, 4999134.00, 12, 2.43, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(395, 'DUMMY-SKU-0395', 'Produk Sampel 395', 'Deskripsi untuk produk sampel nomor 395', 4, 2, 3128771.00, 51, 4.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(396, 'DUMMY-SKU-0396', 'Produk Sampel 396', 'Deskripsi untuk produk sampel nomor 396', 6, 2, 2838579.00, 43, 19.67, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(397, 'DUMMY-SKU-0397', 'Produk Sampel 397', 'Deskripsi untuk produk sampel nomor 397', 7, 4, 4303157.00, 87, 6.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(398, 'DUMMY-SKU-0398', 'Produk Sampel 398', 'Deskripsi untuk produk sampel nomor 398', 2, 3, 72086.00, 107, 17.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(399, 'DUMMY-SKU-0399', 'Produk Sampel 399', 'Deskripsi untuk produk sampel nomor 399', 3, 1, 3350342.00, 102, 12.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(400, 'DUMMY-SKU-0400', 'Produk Sampel 400', 'Deskripsi untuk produk sampel nomor 400', 3, 7, 1927034.00, 35, 2.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(401, 'DUMMY-SKU-0401', 'Produk Sampel 401', 'Deskripsi untuk produk sampel nomor 401', 6, 4, 932788.00, 54, 13.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(402, 'DUMMY-SKU-0402', 'Produk Sampel 402', 'Deskripsi untuk produk sampel nomor 402', 1, 1, 282604.00, 33, 0.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(403, 'DUMMY-SKU-0403', 'Produk Sampel 403', 'Deskripsi untuk produk sampel nomor 403', 3, 6, 2864154.00, 77, 13.68, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(404, 'DUMMY-SKU-0404', 'Produk Sampel 404', 'Deskripsi untuk produk sampel nomor 404', 3, 6, 3645193.00, 45, 11.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(405, 'DUMMY-SKU-0405', 'Produk Sampel 405', 'Deskripsi untuk produk sampel nomor 405', 6, 4, 3360926.00, 14, 4.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(406, 'DUMMY-SKU-0406', 'Produk Sampel 406', 'Deskripsi untuk produk sampel nomor 406', 1, 3, 4273716.00, 22, 1.40, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(407, 'DUMMY-SKU-0407', 'Produk Sampel 407', 'Deskripsi untuk produk sampel nomor 407', 7, 4, 4716187.00, 13, 6.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(408, 'DUMMY-SKU-0408', 'Produk Sampel 408', 'Deskripsi untuk produk sampel nomor 408', 4, 6, 552474.00, 39, 2.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(409, 'DUMMY-SKU-0409', 'Produk Sampel 409', 'Deskripsi untuk produk sampel nomor 409', 6, 6, 1555524.00, 34, 6.41, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(410, 'DUMMY-SKU-0410', 'Produk Sampel 410', 'Deskripsi untuk produk sampel nomor 410', 6, 2, 2836329.00, 29, 5.20, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(411, 'DUMMY-SKU-0411', 'Produk Sampel 411', 'Deskripsi untuk produk sampel nomor 411', 5, 6, 3283085.00, 11, 2.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(412, 'DUMMY-SKU-0412', 'Produk Sampel 412', 'Deskripsi untuk produk sampel nomor 412', 4, 1, 1012849.00, 69, 7.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(413, 'DUMMY-SKU-0413', 'Produk Sampel 413', 'Deskripsi untuk produk sampel nomor 413', 2, 5, 3852963.00, 98, 2.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(414, 'DUMMY-SKU-0414', 'Produk Sampel 414', 'Deskripsi untuk produk sampel nomor 414', 7, 1, 4687882.00, 41, 15.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(415, 'DUMMY-SKU-0415', 'Produk Sampel 415', 'Deskripsi untuk produk sampel nomor 415', 7, 3, 1045520.00, 89, 7.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(416, 'DUMMY-SKU-0416', 'Produk Sampel 416', 'Deskripsi untuk produk sampel nomor 416', 4, 3, 677088.00, 80, 2.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(417, 'DUMMY-SKU-0417', 'Produk Sampel 417', 'Deskripsi untuk produk sampel nomor 417', 4, 7, 2333088.00, 51, 13.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(418, 'DUMMY-SKU-0418', 'Produk Sampel 418', 'Deskripsi untuk produk sampel nomor 418', 1, 3, 4462981.00, 26, 3.42, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(419, 'DUMMY-SKU-0419', 'Produk Sampel 419', 'Deskripsi untuk produk sampel nomor 419', 3, 1, 3646606.00, 30, 17.41, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(420, 'DUMMY-SKU-0420', 'Produk Sampel 420', 'Deskripsi untuk produk sampel nomor 420', 5, 7, 1930321.00, 33, 0.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(421, 'DUMMY-SKU-0421', 'Produk Sampel 421', 'Deskripsi untuk produk sampel nomor 421', 3, 6, 3788635.00, 57, 2.37, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(422, 'DUMMY-SKU-0422', 'Produk Sampel 422', 'Deskripsi untuk produk sampel nomor 422', 1, 3, 1858477.00, 87, 15.43, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(423, 'DUMMY-SKU-0423', 'Produk Sampel 423', 'Deskripsi untuk produk sampel nomor 423', 4, 2, 3305012.00, 68, 19.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(424, 'DUMMY-SKU-0424', 'Produk Sampel 424', 'Deskripsi untuk produk sampel nomor 424', 1, 2, 973600.00, 30, 8.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(425, 'DUMMY-SKU-0425', 'Produk Sampel 425', 'Deskripsi untuk produk sampel nomor 425', 5, 4, 631668.00, 100, 3.59, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(426, 'DUMMY-SKU-0426', 'Produk Sampel 426', 'Deskripsi untuk produk sampel nomor 426', 2, 2, 2815971.00, 30, 7.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(427, 'DUMMY-SKU-0427', 'Produk Sampel 427', 'Deskripsi untuk produk sampel nomor 427', 2, 6, 2752261.00, 38, 16.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(428, 'DUMMY-SKU-0428', 'Produk Sampel 428', 'Deskripsi untuk produk sampel nomor 428', 1, 2, 2994569.00, 51, 6.17, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(429, 'DUMMY-SKU-0429', 'Produk Sampel 429', 'Deskripsi untuk produk sampel nomor 429', 2, 3, 879607.00, 79, 19.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(430, 'DUMMY-SKU-0430', 'Produk Sampel 430', 'Deskripsi untuk produk sampel nomor 430', 6, 6, 2430754.00, 32, 13.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(431, 'DUMMY-SKU-0431', 'Produk Sampel 431', 'Deskripsi untuk produk sampel nomor 431', 6, 5, 4307513.00, 56, 15.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(432, 'DUMMY-SKU-0432', 'Produk Sampel 432', 'Deskripsi untuk produk sampel nomor 432', 3, 3, 599188.00, 42, 5.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(433, 'DUMMY-SKU-0433', 'Produk Sampel 433', 'Deskripsi untuk produk sampel nomor 433', 3, 6, 4766373.00, 53, 6.20, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(434, 'DUMMY-SKU-0434', 'Produk Sampel 434', 'Deskripsi untuk produk sampel nomor 434', 2, 2, 2487995.00, 86, 6.92, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(435, 'DUMMY-SKU-0435', 'Produk Sampel 435', 'Deskripsi untuk produk sampel nomor 435', 3, 1, 4253668.00, 30, 9.31, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(436, 'DUMMY-SKU-0436', 'Produk Sampel 436', 'Deskripsi untuk produk sampel nomor 436', 5, 1, 2268145.00, 103, 6.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(437, 'DUMMY-SKU-0437', 'Produk Sampel 437', 'Deskripsi untuk produk sampel nomor 437', 5, 5, 4563410.00, 84, 0.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(438, 'DUMMY-SKU-0438', 'Produk Sampel 438', 'Deskripsi untuk produk sampel nomor 438', 6, 7, 2560084.00, 69, 9.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(439, 'DUMMY-SKU-0439', 'Produk Sampel 439', 'Deskripsi untuk produk sampel nomor 439', 4, 3, 4904919.00, 102, 13.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(440, 'DUMMY-SKU-0440', 'Produk Sampel 440', 'Deskripsi untuk produk sampel nomor 440', 5, 2, 345947.00, 82, 8.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(441, 'DUMMY-SKU-0441', 'Produk Sampel 441', 'Deskripsi untuk produk sampel nomor 441', 7, 2, 1066025.00, 64, 2.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(442, 'DUMMY-SKU-0442', 'Produk Sampel 442', 'Deskripsi untuk produk sampel nomor 442', 6, 7, 1012254.00, 25, 3.59, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(443, 'DUMMY-SKU-0443', 'Produk Sampel 443', 'Deskripsi untuk produk sampel nomor 443', 3, 4, 1720685.00, 27, 16.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(444, 'DUMMY-SKU-0444', 'Produk Sampel 444', 'Deskripsi untuk produk sampel nomor 444', 5, 6, 4722444.00, 46, 19.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(445, 'DUMMY-SKU-0445', 'Produk Sampel 445', 'Deskripsi untuk produk sampel nomor 445', 7, 3, 167999.00, 29, 17.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(446, 'DUMMY-SKU-0446', 'Produk Sampel 446', 'Deskripsi untuk produk sampel nomor 446', 6, 3, 2934348.00, 82, 17.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(447, 'DUMMY-SKU-0447', 'Produk Sampel 447', 'Deskripsi untuk produk sampel nomor 447', 1, 6, 30080.00, 57, 7.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(448, 'DUMMY-SKU-0448', 'Produk Sampel 448', 'Deskripsi untuk produk sampel nomor 448', 3, 1, 4011397.00, 105, 7.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(449, 'DUMMY-SKU-0449', 'Produk Sampel 449', 'Deskripsi untuk produk sampel nomor 449', 1, 7, 2191843.00, 61, 5.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(450, 'DUMMY-SKU-0450', 'Produk Sampel 450', 'Deskripsi untuk produk sampel nomor 450', 6, 3, 889783.00, 97, 16.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(451, 'DUMMY-SKU-0451', 'Produk Sampel 451', 'Deskripsi untuk produk sampel nomor 451', 5, 4, 2502775.00, 21, 1.85, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(452, 'DUMMY-SKU-0452', 'Produk Sampel 452', 'Deskripsi untuk produk sampel nomor 452', 1, 2, 3066261.00, 63, 16.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(453, 'DUMMY-SKU-0453', 'Produk Sampel 453', 'Deskripsi untuk produk sampel nomor 453', 4, 2, 2250062.00, 70, 13.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(454, 'DUMMY-SKU-0454', 'Produk Sampel 454', 'Deskripsi untuk produk sampel nomor 454', 4, 4, 1429916.00, 83, 16.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(455, 'DUMMY-SKU-0455', 'Produk Sampel 455', 'Deskripsi untuk produk sampel nomor 455', 6, 5, 51156.00, 105, 15.57, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(456, 'DUMMY-SKU-0456', 'Produk Sampel 456', 'Deskripsi untuk produk sampel nomor 456', 7, 5, 675478.00, 90, 12.86, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(457, 'DUMMY-SKU-0457', 'Produk Sampel 457', 'Deskripsi untuk produk sampel nomor 457', 6, 7, 1590092.00, 90, 2.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(458, 'DUMMY-SKU-0458', 'Produk Sampel 458', 'Deskripsi untuk produk sampel nomor 458', 1, 7, 3933923.00, 105, 8.23, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(459, 'DUMMY-SKU-0459', 'Produk Sampel 459', 'Deskripsi untuk produk sampel nomor 459', 2, 5, 3834963.00, 95, 19.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(460, 'DUMMY-SKU-0460', 'Produk Sampel 460', 'Deskripsi untuk produk sampel nomor 460', 2, 2, 3316631.00, 60, 10.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(461, 'DUMMY-SKU-0461', 'Produk Sampel 461', 'Deskripsi untuk produk sampel nomor 461', 1, 7, 2825027.00, 98, 14.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(462, 'DUMMY-SKU-0462', 'Produk Sampel 462', 'Deskripsi untuk produk sampel nomor 462', 7, 4, 3663612.00, 24, 10.50, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(463, 'DUMMY-SKU-0463', 'Produk Sampel 463', 'Deskripsi untuk produk sampel nomor 463', 2, 3, 35859.00, 21, 10.92, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(464, 'DUMMY-SKU-0464', 'Produk Sampel 464', 'Deskripsi untuk produk sampel nomor 464', 3, 2, 324557.00, 70, 17.08, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(465, 'DUMMY-SKU-0465', 'Produk Sampel 465', 'Deskripsi untuk produk sampel nomor 465', 3, 4, 2697898.00, 10, 8.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(466, 'DUMMY-SKU-0466', 'Produk Sampel 466', 'Deskripsi untuk produk sampel nomor 466', 1, 2, 3222103.00, 76, 8.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(467, 'DUMMY-SKU-0467', 'Produk Sampel 467', 'Deskripsi untuk produk sampel nomor 467', 7, 6, 4702847.00, 43, 17.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(468, 'DUMMY-SKU-0468', 'Produk Sampel 468', 'Deskripsi untuk produk sampel nomor 468', 3, 1, 1417791.00, 34, 7.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(469, 'DUMMY-SKU-0469', 'Produk Sampel 469', 'Deskripsi untuk produk sampel nomor 469', 1, 3, 1140183.00, 36, 12.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(470, 'DUMMY-SKU-0470', 'Produk Sampel 470', 'Deskripsi untuk produk sampel nomor 470', 3, 1, 4937256.00, 93, 4.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(471, 'DUMMY-SKU-0471', 'Produk Sampel 471', 'Deskripsi untuk produk sampel nomor 471', 5, 6, 3078675.00, 95, 8.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(472, 'DUMMY-SKU-0472', 'Produk Sampel 472', 'Deskripsi untuk produk sampel nomor 472', 4, 4, 3982162.00, 60, 2.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(473, 'DUMMY-SKU-0473', 'Produk Sampel 473', 'Deskripsi untuk produk sampel nomor 473', 2, 4, 3261558.00, 105, 17.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(474, 'DUMMY-SKU-0474', 'Produk Sampel 474', 'Deskripsi untuk produk sampel nomor 474', 3, 2, 822536.00, 17, 17.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(475, 'DUMMY-SKU-0475', 'Produk Sampel 475', 'Deskripsi untuk produk sampel nomor 475', 1, 1, 3372555.00, 44, 13.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(476, 'DUMMY-SKU-0476', 'Produk Sampel 476', 'Deskripsi untuk produk sampel nomor 476', 3, 7, 2332575.00, 63, 5.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(477, 'DUMMY-SKU-0477', 'Produk Sampel 477', 'Deskripsi untuk produk sampel nomor 477', 5, 6, 3707818.00, 47, 13.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(478, 'DUMMY-SKU-0478', 'Produk Sampel 478', 'Deskripsi untuk produk sampel nomor 478', 1, 5, 4905223.00, 98, 9.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(479, 'DUMMY-SKU-0479', 'Produk Sampel 479', 'Deskripsi untuk produk sampel nomor 479', 6, 4, 1894696.00, 30, 17.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(480, 'DUMMY-SKU-0480', 'Produk Sampel 480', 'Deskripsi untuk produk sampel nomor 480', 6, 4, 398257.00, 93, 18.83, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(481, 'DUMMY-SKU-0481', 'Produk Sampel 481', 'Deskripsi untuk produk sampel nomor 481', 2, 1, 4707364.00, 50, 4.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(482, 'DUMMY-SKU-0482', 'Produk Sampel 482', 'Deskripsi untuk produk sampel nomor 482', 7, 5, 4275232.00, 28, 7.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(483, 'DUMMY-SKU-0483', 'Produk Sampel 483', 'Deskripsi untuk produk sampel nomor 483', 3, 5, 4767873.00, 105, 18.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(484, 'DUMMY-SKU-0484', 'Produk Sampel 484', 'Deskripsi untuk produk sampel nomor 484', 6, 1, 1421988.00, 13, 6.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(485, 'DUMMY-SKU-0485', 'Produk Sampel 485', 'Deskripsi untuk produk sampel nomor 485', 4, 3, 1529967.00, 62, 14.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(486, 'DUMMY-SKU-0486', 'Produk Sampel 486', 'Deskripsi untuk produk sampel nomor 486', 7, 6, 3847770.00, 72, 16.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(487, 'DUMMY-SKU-0487', 'Produk Sampel 487', 'Deskripsi untuk produk sampel nomor 487', 2, 6, 1368566.00, 103, 16.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(488, 'DUMMY-SKU-0488', 'Produk Sampel 488', 'Deskripsi untuk produk sampel nomor 488', 3, 4, 1316825.00, 92, 7.05, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(489, 'DUMMY-SKU-0489', 'Produk Sampel 489', 'Deskripsi untuk produk sampel nomor 489', 2, 2, 2445875.00, 77, 18.58, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(490, 'DUMMY-SKU-0490', 'Produk Sampel 490', 'Deskripsi untuk produk sampel nomor 490', 5, 2, 367722.00, 95, 1.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(491, 'DUMMY-SKU-0491', 'Produk Sampel 491', 'Deskripsi untuk produk sampel nomor 491', 6, 5, 732370.00, 72, 14.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(492, 'DUMMY-SKU-0492', 'Produk Sampel 492', 'Deskripsi untuk produk sampel nomor 492', 5, 1, 3580177.00, 27, 14.27, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(493, 'DUMMY-SKU-0493', 'Produk Sampel 493', 'Deskripsi untuk produk sampel nomor 493', 1, 1, 485545.00, 45, 10.31, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(494, 'DUMMY-SKU-0494', 'Produk Sampel 494', 'Deskripsi untuk produk sampel nomor 494', 4, 6, 3886113.00, 45, 9.35, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(495, 'DUMMY-SKU-0495', 'Produk Sampel 495', 'Deskripsi untuk produk sampel nomor 495', 2, 6, 1719509.00, 37, 6.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(496, 'DUMMY-SKU-0496', 'Produk Sampel 496', 'Deskripsi untuk produk sampel nomor 496', 7, 3, 4640420.00, 82, 16.86, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(497, 'DUMMY-SKU-0497', 'Produk Sampel 497', 'Deskripsi untuk produk sampel nomor 497', 1, 5, 4469354.00, 78, 15.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(498, 'DUMMY-SKU-0498', 'Produk Sampel 498', 'Deskripsi untuk produk sampel nomor 498', 6, 3, 2365376.00, 47, 9.82, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(499, 'DUMMY-SKU-0499', 'Produk Sampel 499', 'Deskripsi untuk produk sampel nomor 499', 3, 7, 567346.00, 66, 10.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(500, 'DUMMY-SKU-0500', 'Produk Sampel 500', 'Deskripsi untuk produk sampel nomor 500', 6, 4, 4739374.00, 43, 17.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(501, 'DUMMY-SKU-0501', 'Produk Sampel 501', 'Deskripsi untuk produk sampel nomor 501', 2, 4, 401285.00, 85, 10.93, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(502, 'DUMMY-SKU-0502', 'Produk Sampel 502', 'Deskripsi untuk produk sampel nomor 502', 4, 5, 2917733.00, 26, 1.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(503, 'DUMMY-SKU-0503', 'Produk Sampel 503', 'Deskripsi untuk produk sampel nomor 503', 7, 3, 3833951.00, 103, 7.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(504, 'DUMMY-SKU-0504', 'Produk Sampel 504', 'Deskripsi untuk produk sampel nomor 504', 1, 7, 3759354.00, 98, 3.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(505, 'DUMMY-SKU-0505', 'Produk Sampel 505', 'Deskripsi untuk produk sampel nomor 505', 2, 6, 1086549.00, 75, 12.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(506, 'DUMMY-SKU-0506', 'Produk Sampel 506', 'Deskripsi untuk produk sampel nomor 506', 2, 7, 1826410.00, 99, 7.31, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(507, 'DUMMY-SKU-0507', 'Produk Sampel 507', 'Deskripsi untuk produk sampel nomor 507', 1, 5, 2613108.00, 95, 13.95, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(508, 'DUMMY-SKU-0508', 'Produk Sampel 508', 'Deskripsi untuk produk sampel nomor 508', 7, 4, 3206899.00, 87, 19.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(509, 'DUMMY-SKU-0509', 'Produk Sampel 509', 'Deskripsi untuk produk sampel nomor 509', 4, 3, 2880971.00, 81, 17.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(510, 'DUMMY-SKU-0510', 'Produk Sampel 510', 'Deskripsi untuk produk sampel nomor 510', 2, 2, 2845656.00, 30, 7.01, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(511, 'DUMMY-SKU-0511', 'Produk Sampel 511', 'Deskripsi untuk produk sampel nomor 511', 1, 4, 4956429.00, 67, 18.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(512, 'DUMMY-SKU-0512', 'Produk Sampel 512', 'Deskripsi untuk produk sampel nomor 512', 6, 3, 1928341.00, 91, 18.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(513, 'DUMMY-SKU-0513', 'Produk Sampel 513', 'Deskripsi untuk produk sampel nomor 513', 2, 7, 2580289.00, 69, 8.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(514, 'DUMMY-SKU-0514', 'Produk Sampel 514', 'Deskripsi untuk produk sampel nomor 514', 3, 3, 29099.00, 91, 1.49, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(515, 'DUMMY-SKU-0515', 'Produk Sampel 515', 'Deskripsi untuk produk sampel nomor 515', 7, 2, 3601480.00, 84, 11.40, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(516, 'DUMMY-SKU-0516', 'Produk Sampel 516', 'Deskripsi untuk produk sampel nomor 516', 5, 2, 2801494.00, 109, 5.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(517, 'DUMMY-SKU-0517', 'Produk Sampel 517', 'Deskripsi untuk produk sampel nomor 517', 3, 2, 4734601.00, 11, 4.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(518, 'DUMMY-SKU-0518', 'Produk Sampel 518', 'Deskripsi untuk produk sampel nomor 518', 1, 7, 463172.00, 88, 13.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(519, 'DUMMY-SKU-0519', 'Produk Sampel 519', 'Deskripsi untuk produk sampel nomor 519', 1, 1, 361291.00, 39, 5.13, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(520, 'DUMMY-SKU-0520', 'Produk Sampel 520', 'Deskripsi untuk produk sampel nomor 520', 3, 2, 3042857.00, 68, 2.02, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(521, 'DUMMY-SKU-0521', 'Produk Sampel 521', 'Deskripsi untuk produk sampel nomor 521', 6, 3, 3110571.00, 11, 4.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(522, 'DUMMY-SKU-0522', 'Produk Sampel 522', 'Deskripsi untuk produk sampel nomor 522', 1, 4, 1368779.00, 105, 19.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(523, 'DUMMY-SKU-0523', 'Produk Sampel 523', 'Deskripsi untuk produk sampel nomor 523', 7, 1, 770760.00, 79, 0.10, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(524, 'DUMMY-SKU-0524', 'Produk Sampel 524', 'Deskripsi untuk produk sampel nomor 524', 7, 5, 1947690.00, 13, 0.54, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(525, 'DUMMY-SKU-0525', 'Produk Sampel 525', 'Deskripsi untuk produk sampel nomor 525', 7, 7, 3238710.00, 54, 5.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(526, 'DUMMY-SKU-0526', 'Produk Sampel 526', 'Deskripsi untuk produk sampel nomor 526', 1, 4, 1499013.00, 108, 1.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(527, 'DUMMY-SKU-0527', 'Produk Sampel 527', 'Deskripsi untuk produk sampel nomor 527', 2, 2, 1727297.00, 11, 0.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(528, 'DUMMY-SKU-0528', 'Produk Sampel 528', 'Deskripsi untuk produk sampel nomor 528', 2, 6, 1193739.00, 102, 18.12, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(529, 'DUMMY-SKU-0529', 'Produk Sampel 529', 'Deskripsi untuk produk sampel nomor 529', 6, 7, 3722664.00, 83, 9.22, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(530, 'DUMMY-SKU-0530', 'Produk Sampel 530', 'Deskripsi untuk produk sampel nomor 530', 1, 7, 3540391.00, 68, 15.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(531, 'DUMMY-SKU-0531', 'Produk Sampel 531', 'Deskripsi untuk produk sampel nomor 531', 2, 4, 160190.00, 72, 0.72, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(532, 'DUMMY-SKU-0532', 'Produk Sampel 532', 'Deskripsi untuk produk sampel nomor 532', 2, 3, 3655550.00, 80, 6.51, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(533, 'DUMMY-SKU-0533', 'Produk Sampel 533', 'Deskripsi untuk produk sampel nomor 533', 4, 4, 700422.00, 21, 3.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(534, 'DUMMY-SKU-0534', 'Produk Sampel 534', 'Deskripsi untuk produk sampel nomor 534', 3, 4, 2514505.00, 99, 19.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(535, 'DUMMY-SKU-0535', 'Produk Sampel 535', 'Deskripsi untuk produk sampel nomor 535', 1, 6, 1382381.00, 28, 2.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(536, 'DUMMY-SKU-0536', 'Produk Sampel 536', 'Deskripsi untuk produk sampel nomor 536', 1, 6, 677166.00, 20, 2.89, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(537, 'DUMMY-SKU-0537', 'Produk Sampel 537', 'Deskripsi untuk produk sampel nomor 537', 3, 4, 591529.00, 34, 17.15, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(538, 'DUMMY-SKU-0538', 'Produk Sampel 538', 'Deskripsi untuk produk sampel nomor 538', 4, 2, 643691.00, 28, 10.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(539, 'DUMMY-SKU-0539', 'Produk Sampel 539', 'Deskripsi untuk produk sampel nomor 539', 1, 1, 3393433.00, 45, 15.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(540, 'DUMMY-SKU-0540', 'Produk Sampel 540', 'Deskripsi untuk produk sampel nomor 540', 5, 3, 1587272.00, 80, 11.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(541, 'DUMMY-SKU-0541', 'Produk Sampel 541', 'Deskripsi untuk produk sampel nomor 541', 6, 2, 4311386.00, 64, 2.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(542, 'DUMMY-SKU-0542', 'Produk Sampel 542', 'Deskripsi untuk produk sampel nomor 542', 1, 7, 1277548.00, 70, 5.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(543, 'DUMMY-SKU-0543', 'Produk Sampel 543', 'Deskripsi untuk produk sampel nomor 543', 4, 7, 4406130.00, 78, 16.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(544, 'DUMMY-SKU-0544', 'Produk Sampel 544', 'Deskripsi untuk produk sampel nomor 544', 7, 4, 1287675.00, 107, 2.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(545, 'DUMMY-SKU-0545', 'Produk Sampel 545', 'Deskripsi untuk produk sampel nomor 545', 5, 6, 1321581.00, 91, 5.68, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(546, 'DUMMY-SKU-0546', 'Produk Sampel 546', 'Deskripsi untuk produk sampel nomor 546', 7, 7, 4116393.00, 39, 0.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(547, 'DUMMY-SKU-0547', 'Produk Sampel 547', 'Deskripsi untuk produk sampel nomor 547', 2, 6, 3226399.00, 81, 13.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(548, 'DUMMY-SKU-0548', 'Produk Sampel 548', 'Deskripsi untuk produk sampel nomor 548', 2, 6, 1344497.00, 21, 15.68, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(549, 'DUMMY-SKU-0549', 'Produk Sampel 549', 'Deskripsi untuk produk sampel nomor 549', 4, 3, 1807761.00, 69, 18.17, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(550, 'DUMMY-SKU-0550', 'Produk Sampel 550', 'Deskripsi untuk produk sampel nomor 550', 6, 7, 2425565.00, 71, 12.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(551, 'DUMMY-SKU-0551', 'Produk Sampel 551', 'Deskripsi untuk produk sampel nomor 551', 2, 3, 1112875.00, 102, 19.00, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(552, 'DUMMY-SKU-0552', 'Produk Sampel 552', 'Deskripsi untuk produk sampel nomor 552', 7, 7, 4769079.00, 95, 8.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(553, 'DUMMY-SKU-0553', 'Produk Sampel 553', 'Deskripsi untuk produk sampel nomor 553', 5, 6, 1653309.00, 20, 10.69, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(554, 'DUMMY-SKU-0554', 'Produk Sampel 554', 'Deskripsi untuk produk sampel nomor 554', 3, 1, 2434863.00, 22, 3.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(555, 'DUMMY-SKU-0555', 'Produk Sampel 555', 'Deskripsi untuk produk sampel nomor 555', 4, 7, 2359644.00, 45, 7.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(556, 'DUMMY-SKU-0556', 'Produk Sampel 556', 'Deskripsi untuk produk sampel nomor 556', 6, 7, 1493141.00, 73, 5.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(557, 'DUMMY-SKU-0557', 'Produk Sampel 557', 'Deskripsi untuk produk sampel nomor 557', 4, 6, 1680160.00, 41, 11.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(558, 'DUMMY-SKU-0558', 'Produk Sampel 558', 'Deskripsi untuk produk sampel nomor 558', 7, 1, 3092330.00, 86, 19.35, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(559, 'DUMMY-SKU-0559', 'Produk Sampel 559', 'Deskripsi untuk produk sampel nomor 559', 4, 6, 598250.00, 47, 10.27, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(560, 'DUMMY-SKU-0560', 'Produk Sampel 560', 'Deskripsi untuk produk sampel nomor 560', 3, 5, 3672900.00, 95, 1.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(561, 'DUMMY-SKU-0561', 'Produk Sampel 561', 'Deskripsi untuk produk sampel nomor 561', 7, 1, 4843278.00, 57, 9.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(562, 'DUMMY-SKU-0562', 'Produk Sampel 562', 'Deskripsi untuk produk sampel nomor 562', 7, 1, 4009818.00, 80, 2.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(563, 'DUMMY-SKU-0563', 'Produk Sampel 563', 'Deskripsi untuk produk sampel nomor 563', 4, 1, 255870.00, 102, 9.85, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(564, 'DUMMY-SKU-0564', 'Produk Sampel 564', 'Deskripsi untuk produk sampel nomor 564', 5, 6, 711936.00, 33, 15.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(565, 'DUMMY-SKU-0565', 'Produk Sampel 565', 'Deskripsi untuk produk sampel nomor 565', 1, 1, 618982.00, 51, 14.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(566, 'DUMMY-SKU-0566', 'Produk Sampel 566', 'Deskripsi untuk produk sampel nomor 566', 3, 6, 2688208.00, 56, 14.45, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(567, 'DUMMY-SKU-0567', 'Produk Sampel 567', 'Deskripsi untuk produk sampel nomor 567', 2, 6, 2384511.00, 104, 5.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(568, 'DUMMY-SKU-0568', 'Produk Sampel 568', 'Deskripsi untuk produk sampel nomor 568', 5, 2, 1609293.00, 98, 9.80, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(569, 'DUMMY-SKU-0569', 'Produk Sampel 569', 'Deskripsi untuk produk sampel nomor 569', 6, 3, 1960944.00, 105, 12.04, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(570, 'DUMMY-SKU-0570', 'Produk Sampel 570', 'Deskripsi untuk produk sampel nomor 570', 1, 6, 4024766.00, 60, 2.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(571, 'DUMMY-SKU-0571', 'Produk Sampel 571', 'Deskripsi untuk produk sampel nomor 571', 1, 2, 2710539.00, 27, 5.41, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(572, 'DUMMY-SKU-0572', 'Produk Sampel 572', 'Deskripsi untuk produk sampel nomor 572', 6, 2, 2717025.00, 24, 2.44, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(573, 'DUMMY-SKU-0573', 'Produk Sampel 573', 'Deskripsi untuk produk sampel nomor 573', 1, 3, 1640467.00, 68, 18.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(574, 'DUMMY-SKU-0574', 'Produk Sampel 574', 'Deskripsi untuk produk sampel nomor 574', 7, 6, 2142628.00, 70, 14.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(575, 'DUMMY-SKU-0575', 'Produk Sampel 575', 'Deskripsi untuk produk sampel nomor 575', 7, 1, 4433226.00, 24, 1.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(576, 'DUMMY-SKU-0576', 'Produk Sampel 576', 'Deskripsi untuk produk sampel nomor 576', 7, 5, 1039336.00, 25, 2.75, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(577, 'DUMMY-SKU-0577', 'Produk Sampel 577', 'Deskripsi untuk produk sampel nomor 577', 2, 5, 3436442.00, 53, 2.28, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(578, 'DUMMY-SKU-0578', 'Produk Sampel 578', 'Deskripsi untuk produk sampel nomor 578', 2, 7, 3883564.00, 26, 10.24, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(579, 'DUMMY-SKU-0579', 'Produk Sampel 579', 'Deskripsi untuk produk sampel nomor 579', 1, 5, 891258.00, 101, 0.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(580, 'DUMMY-SKU-0580', 'Produk Sampel 580', 'Deskripsi untuk produk sampel nomor 580', 3, 7, 3590161.00, 69, 17.14, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23');
INSERT INTO `products` (`id`, `sku`, `name`, `description`, `category_id`, `supplier_id`, `unit_price`, `minimum_stock`, `weight`, `status`, `created_at`, `updated_at`) VALUES
(581, 'DUMMY-SKU-0581', 'Produk Sampel 581', 'Deskripsi untuk produk sampel nomor 581', 4, 6, 1601555.00, 47, 18.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(582, 'DUMMY-SKU-0582', 'Produk Sampel 582', 'Deskripsi untuk produk sampel nomor 582', 4, 5, 2574931.00, 91, 10.86, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(583, 'DUMMY-SKU-0583', 'Produk Sampel 583', 'Deskripsi untuk produk sampel nomor 583', 2, 5, 1535749.00, 80, 12.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(584, 'DUMMY-SKU-0584', 'Produk Sampel 584', 'Deskripsi untuk produk sampel nomor 584', 7, 5, 2211339.00, 44, 8.58, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(585, 'DUMMY-SKU-0585', 'Produk Sampel 585', 'Deskripsi untuk produk sampel nomor 585', 1, 1, 1228745.00, 104, 19.61, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(586, 'DUMMY-SKU-0586', 'Produk Sampel 586', 'Deskripsi untuk produk sampel nomor 586', 1, 3, 2733673.00, 80, 17.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(587, 'DUMMY-SKU-0587', 'Produk Sampel 587', 'Deskripsi untuk produk sampel nomor 587', 2, 5, 1272266.00, 57, 12.86, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(588, 'DUMMY-SKU-0588', 'Produk Sampel 588', 'Deskripsi untuk produk sampel nomor 588', 6, 6, 5000001.00, 53, 3.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(589, 'DUMMY-SKU-0589', 'Produk Sampel 589', 'Deskripsi untuk produk sampel nomor 589', 5, 4, 3530463.00, 109, 17.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(590, 'DUMMY-SKU-0590', 'Produk Sampel 590', 'Deskripsi untuk produk sampel nomor 590', 3, 2, 123606.00, 53, 2.48, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(591, 'DUMMY-SKU-0591', 'Produk Sampel 591', 'Deskripsi untuk produk sampel nomor 591', 2, 1, 2106269.00, 103, 8.68, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(592, 'DUMMY-SKU-0592', 'Produk Sampel 592', 'Deskripsi untuk produk sampel nomor 592', 3, 3, 4400474.00, 36, 13.96, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(593, 'DUMMY-SKU-0593', 'Produk Sampel 593', 'Deskripsi untuk produk sampel nomor 593', 5, 2, 1566328.00, 86, 18.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(594, 'DUMMY-SKU-0594', 'Produk Sampel 594', 'Deskripsi untuk produk sampel nomor 594', 2, 2, 3709306.00, 101, 6.79, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(595, 'DUMMY-SKU-0595', 'Produk Sampel 595', 'Deskripsi untuk produk sampel nomor 595', 7, 5, 3299420.00, 30, 0.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(596, 'DUMMY-SKU-0596', 'Produk Sampel 596', 'Deskripsi untuk produk sampel nomor 596', 5, 7, 2973038.00, 42, 17.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(597, 'DUMMY-SKU-0597', 'Produk Sampel 597', 'Deskripsi untuk produk sampel nomor 597', 2, 6, 1162190.00, 82, 18.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(598, 'DUMMY-SKU-0598', 'Produk Sampel 598', 'Deskripsi untuk produk sampel nomor 598', 4, 5, 4472591.00, 53, 10.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(599, 'DUMMY-SKU-0599', 'Produk Sampel 599', 'Deskripsi untuk produk sampel nomor 599', 2, 3, 2350388.00, 23, 5.94, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(600, 'DUMMY-SKU-0600', 'Produk Sampel 600', 'Deskripsi untuk produk sampel nomor 600', 1, 3, 2672179.00, 76, 14.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(601, 'DUMMY-SKU-0601', 'Produk Sampel 601', 'Deskripsi untuk produk sampel nomor 601', 6, 3, 3010276.00, 105, 19.14, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(602, 'DUMMY-SKU-0602', 'Produk Sampel 602', 'Deskripsi untuk produk sampel nomor 602', 7, 5, 3508284.00, 54, 2.52, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(603, 'DUMMY-SKU-0603', 'Produk Sampel 603', 'Deskripsi untuk produk sampel nomor 603', 2, 7, 912284.00, 100, 19.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(604, 'DUMMY-SKU-0604', 'Produk Sampel 604', 'Deskripsi untuk produk sampel nomor 604', 2, 7, 796367.00, 108, 8.70, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(605, 'DUMMY-SKU-0605', 'Produk Sampel 605', 'Deskripsi untuk produk sampel nomor 605', 2, 6, 646244.00, 48, 11.03, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(606, 'DUMMY-SKU-0606', 'Produk Sampel 606', 'Deskripsi untuk produk sampel nomor 606', 5, 2, 2383206.00, 75, 16.77, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(607, 'DUMMY-SKU-0607', 'Produk Sampel 607', 'Deskripsi untuk produk sampel nomor 607', 2, 4, 881358.00, 28, 8.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(608, 'DUMMY-SKU-0608', 'Produk Sampel 608', 'Deskripsi untuk produk sampel nomor 608', 4, 1, 3573788.00, 64, 11.64, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(609, 'DUMMY-SKU-0609', 'Produk Sampel 609', 'Deskripsi untuk produk sampel nomor 609', 2, 4, 4858148.00, 30, 2.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(610, 'DUMMY-SKU-0610', 'Produk Sampel 610', 'Deskripsi untuk produk sampel nomor 610', 7, 5, 27495.00, 32, 2.76, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(611, 'DUMMY-SKU-0611', 'Produk Sampel 611', 'Deskripsi untuk produk sampel nomor 611', 7, 4, 2716053.00, 31, 9.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(612, 'DUMMY-SKU-0612', 'Produk Sampel 612', 'Deskripsi untuk produk sampel nomor 612', 5, 1, 2186719.00, 94, 18.50, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(613, 'DUMMY-SKU-0613', 'Produk Sampel 613', 'Deskripsi untuk produk sampel nomor 613', 1, 4, 3099373.00, 50, 3.29, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(614, 'DUMMY-SKU-0614', 'Produk Sampel 614', 'Deskripsi untuk produk sampel nomor 614', 5, 4, 2892570.00, 57, 13.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(615, 'DUMMY-SKU-0615', 'Produk Sampel 615', 'Deskripsi untuk produk sampel nomor 615', 6, 1, 1082768.00, 77, 14.84, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(616, 'DUMMY-SKU-0616', 'Produk Sampel 616', 'Deskripsi untuk produk sampel nomor 616', 5, 1, 1878443.00, 76, 4.07, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(617, 'DUMMY-SKU-0617', 'Produk Sampel 617', 'Deskripsi untuk produk sampel nomor 617', 1, 3, 281735.00, 13, 0.47, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(618, 'DUMMY-SKU-0618', 'Produk Sampel 618', 'Deskripsi untuk produk sampel nomor 618', 7, 7, 1787780.00, 29, 18.22, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(619, 'DUMMY-SKU-0619', 'Produk Sampel 619', 'Deskripsi untuk produk sampel nomor 619', 7, 1, 1204673.00, 24, 0.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(620, 'DUMMY-SKU-0620', 'Produk Sampel 620', 'Deskripsi untuk produk sampel nomor 620', 5, 2, 152489.00, 65, 13.91, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(621, 'DUMMY-SKU-0621', 'Produk Sampel 621', 'Deskripsi untuk produk sampel nomor 621', 6, 7, 4875526.00, 36, 8.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(622, 'DUMMY-SKU-0622', 'Produk Sampel 622', 'Deskripsi untuk produk sampel nomor 622', 2, 6, 2035904.00, 72, 18.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(623, 'DUMMY-SKU-0623', 'Produk Sampel 623', 'Deskripsi untuk produk sampel nomor 623', 5, 5, 895517.00, 106, 6.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(624, 'DUMMY-SKU-0624', 'Produk Sampel 624', 'Deskripsi untuk produk sampel nomor 624', 5, 1, 3852824.00, 59, 3.53, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(625, 'DUMMY-SKU-0625', 'Produk Sampel 625', 'Deskripsi untuk produk sampel nomor 625', 3, 3, 2995200.00, 105, 0.13, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(626, 'DUMMY-SKU-0626', 'Produk Sampel 626', 'Deskripsi untuk produk sampel nomor 626', 1, 5, 4374111.00, 50, 8.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(627, 'DUMMY-SKU-0627', 'Produk Sampel 627', 'Deskripsi untuk produk sampel nomor 627', 6, 6, 1670887.00, 54, 4.55, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(628, 'DUMMY-SKU-0628', 'Produk Sampel 628', 'Deskripsi untuk produk sampel nomor 628', 6, 2, 4339132.00, 70, 8.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(629, 'DUMMY-SKU-0629', 'Produk Sampel 629', 'Deskripsi untuk produk sampel nomor 629', 2, 1, 1885092.00, 89, 17.22, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(630, 'DUMMY-SKU-0630', 'Produk Sampel 630', 'Deskripsi untuk produk sampel nomor 630', 7, 7, 3791552.00, 22, 7.19, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(631, 'DUMMY-SKU-0631', 'Produk Sampel 631', 'Deskripsi untuk produk sampel nomor 631', 3, 7, 2151373.00, 46, 11.32, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(632, 'DUMMY-SKU-0632', 'Produk Sampel 632', 'Deskripsi untuk produk sampel nomor 632', 5, 6, 4618370.00, 30, 4.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(633, 'DUMMY-SKU-0633', 'Produk Sampel 633', 'Deskripsi untuk produk sampel nomor 633', 5, 2, 2002481.00, 39, 5.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(634, 'DUMMY-SKU-0634', 'Produk Sampel 634', 'Deskripsi untuk produk sampel nomor 634', 4, 4, 4085722.00, 88, 9.88, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(635, 'DUMMY-SKU-0635', 'Produk Sampel 635', 'Deskripsi untuk produk sampel nomor 635', 1, 7, 2527091.00, 76, 16.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(636, 'DUMMY-SKU-0636', 'Produk Sampel 636', 'Deskripsi untuk produk sampel nomor 636', 1, 7, 2319230.00, 59, 1.90, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(637, 'DUMMY-SKU-0637', 'Produk Sampel 637', 'Deskripsi untuk produk sampel nomor 637', 7, 4, 4471734.00, 88, 5.36, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(638, 'DUMMY-SKU-0638', 'Produk Sampel 638', 'Deskripsi untuk produk sampel nomor 638', 7, 7, 4924905.00, 11, 2.39, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(639, 'DUMMY-SKU-0639', 'Produk Sampel 639', 'Deskripsi untuk produk sampel nomor 639', 4, 3, 293080.00, 38, 5.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(640, 'DUMMY-SKU-0640', 'Produk Sampel 640', 'Deskripsi untuk produk sampel nomor 640', 4, 3, 3231101.00, 15, 7.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(641, 'DUMMY-SKU-0641', 'Produk Sampel 641', 'Deskripsi untuk produk sampel nomor 641', 5, 6, 2345502.00, 91, 13.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(642, 'DUMMY-SKU-0642', 'Produk Sampel 642', 'Deskripsi untuk produk sampel nomor 642', 7, 5, 2147962.00, 29, 14.26, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(643, 'DUMMY-SKU-0643', 'Produk Sampel 643', 'Deskripsi untuk produk sampel nomor 643', 7, 5, 976495.00, 24, 3.25, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(644, 'DUMMY-SKU-0644', 'Produk Sampel 644', 'Deskripsi untuk produk sampel nomor 644', 3, 2, 1066000.00, 40, 18.42, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(645, 'DUMMY-SKU-0645', 'Produk Sampel 645', 'Deskripsi untuk produk sampel nomor 645', 5, 4, 2752453.00, 34, 11.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(646, 'DUMMY-SKU-0646', 'Produk Sampel 646', 'Deskripsi untuk produk sampel nomor 646', 2, 1, 3519710.00, 51, 19.34, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(647, 'DUMMY-SKU-0647', 'Produk Sampel 647', 'Deskripsi untuk produk sampel nomor 647', 4, 7, 416495.00, 63, 8.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(648, 'DUMMY-SKU-0648', 'Produk Sampel 648', 'Deskripsi untuk produk sampel nomor 648', 4, 3, 1730279.00, 65, 14.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(649, 'DUMMY-SKU-0649', 'Produk Sampel 649', 'Deskripsi untuk produk sampel nomor 649', 7, 6, 3643972.00, 52, 19.17, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(650, 'DUMMY-SKU-0650', 'Produk Sampel 650', 'Deskripsi untuk produk sampel nomor 650', 4, 5, 2091023.00, 45, 10.56, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(651, 'DUMMY-SKU-0651', 'Produk Sampel 651', 'Deskripsi untuk produk sampel nomor 651', 4, 2, 1464062.00, 98, 11.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(652, 'DUMMY-SKU-0652', 'Produk Sampel 652', 'Deskripsi untuk produk sampel nomor 652', 2, 1, 4062514.00, 100, 1.65, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(653, 'DUMMY-SKU-0653', 'Produk Sampel 653', 'Deskripsi untuk produk sampel nomor 653', 5, 2, 4132024.00, 70, 10.78, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(654, 'DUMMY-SKU-0654', 'Produk Sampel 654', 'Deskripsi untuk produk sampel nomor 654', 7, 6, 234008.00, 13, 1.21, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(655, 'DUMMY-SKU-0655', 'Produk Sampel 655', 'Deskripsi untuk produk sampel nomor 655', 2, 5, 3770878.00, 91, 16.62, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(656, 'DUMMY-SKU-0656', 'Produk Sampel 656', 'Deskripsi untuk produk sampel nomor 656', 5, 7, 2871625.00, 19, 15.18, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(657, 'DUMMY-SKU-0657', 'Produk Sampel 657', 'Deskripsi untuk produk sampel nomor 657', 4, 2, 2013338.00, 58, 4.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(658, 'DUMMY-SKU-0658', 'Produk Sampel 658', 'Deskripsi untuk produk sampel nomor 658', 5, 6, 4558411.00, 24, 19.87, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(659, 'DUMMY-SKU-0659', 'Produk Sampel 659', 'Deskripsi untuk produk sampel nomor 659', 4, 5, 2104959.00, 42, 7.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(660, 'DUMMY-SKU-0660', 'Produk Sampel 660', 'Deskripsi untuk produk sampel nomor 660', 6, 1, 4811381.00, 62, 14.63, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(661, 'DUMMY-SKU-0661', 'Produk Sampel 661', 'Deskripsi untuk produk sampel nomor 661', 1, 2, 2971379.00, 58, 12.99, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(662, 'DUMMY-SKU-0662', 'Produk Sampel 662', 'Deskripsi untuk produk sampel nomor 662', 6, 7, 1308877.00, 65, 0.33, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(663, 'DUMMY-SKU-0663', 'Produk Sampel 663', 'Deskripsi untuk produk sampel nomor 663', 3, 7, 1239376.00, 69, 4.67, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(664, 'DUMMY-SKU-0664', 'Produk Sampel 664', 'Deskripsi untuk produk sampel nomor 664', 3, 1, 2712280.00, 42, 0.30, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(665, 'DUMMY-SKU-0665', 'Produk Sampel 665', 'Deskripsi untuk produk sampel nomor 665', 1, 3, 2134430.00, 24, 8.66, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(666, 'DUMMY-SKU-0666', 'Produk Sampel 666', 'Deskripsi untuk produk sampel nomor 666', 6, 3, 1889742.00, 106, 13.73, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(667, 'DUMMY-SKU-0667', 'Produk Sampel 667', 'Deskripsi untuk produk sampel nomor 667', 4, 4, 1392903.00, 77, 11.09, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(668, 'DUMMY-SKU-0668', 'Produk Sampel 668', 'Deskripsi untuk produk sampel nomor 668', 6, 7, 3014534.00, 24, 18.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(669, 'DUMMY-SKU-0669', 'Produk Sampel 669', 'Deskripsi untuk produk sampel nomor 669', 2, 3, 653057.00, 64, 6.74, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(670, 'DUMMY-SKU-0670', 'Produk Sampel 670', 'Deskripsi untuk produk sampel nomor 670', 1, 2, 3416958.00, 104, 13.59, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(671, 'DUMMY-SKU-0671', 'Produk Sampel 671', 'Deskripsi untuk produk sampel nomor 671', 4, 5, 4009900.00, 104, 6.57, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(672, 'DUMMY-SKU-0672', 'Produk Sampel 672', 'Deskripsi untuk produk sampel nomor 672', 6, 7, 1972355.00, 21, 8.13, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(673, 'DUMMY-SKU-0673', 'Produk Sampel 673', 'Deskripsi untuk produk sampel nomor 673', 5, 1, 2507628.00, 30, 11.11, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(674, 'DUMMY-SKU-0674', 'Produk Sampel 674', 'Deskripsi untuk produk sampel nomor 674', 1, 7, 2158928.00, 37, 1.46, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(675, 'DUMMY-SKU-0675', 'Produk Sampel 675', 'Deskripsi untuk produk sampel nomor 675', 4, 3, 2755008.00, 56, 14.06, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(676, 'DUMMY-SKU-0676', 'Produk Sampel 676', 'Deskripsi untuk produk sampel nomor 676', 1, 3, 1708197.00, 84, 14.38, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(677, 'DUMMY-SKU-0677', 'Produk Sampel 677', 'Deskripsi untuk produk sampel nomor 677', 3, 4, 2814055.00, 37, 13.71, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(678, 'DUMMY-SKU-0678', 'Produk Sampel 678', 'Deskripsi untuk produk sampel nomor 678', 5, 7, 3328772.00, 76, 7.01, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(679, 'DUMMY-SKU-0679', 'Produk Sampel 679', 'Deskripsi untuk produk sampel nomor 679', 6, 5, 3814295.00, 14, 18.81, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(680, 'DUMMY-SKU-0680', 'Produk Sampel 680', 'Deskripsi untuk produk sampel nomor 680', 4, 7, 4883981.00, 20, 12.31, 'active', '2025-07-31 03:55:23', '2025-07-31 03:55:23'),
(681, 'DUMMY-SKU-0681', 'Produk Sampel 681', 'Deskripsi untuk produk sampel nomor 681', 6, 6, 4688027.00, 29, 3.96, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(682, 'DUMMY-SKU-0682', 'Produk Sampel 682', 'Deskripsi untuk produk sampel nomor 682', 3, 2, 723157.00, 106, 8.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(683, 'DUMMY-SKU-0683', 'Produk Sampel 683', 'Deskripsi untuk produk sampel nomor 683', 2, 6, 156151.00, 107, 15.60, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(684, 'DUMMY-SKU-0684', 'Produk Sampel 684', 'Deskripsi untuk produk sampel nomor 684', 7, 4, 2286486.00, 97, 0.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(685, 'DUMMY-SKU-0685', 'Produk Sampel 685', 'Deskripsi untuk produk sampel nomor 685', 4, 3, 2311639.00, 23, 6.30, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(686, 'DUMMY-SKU-0686', 'Produk Sampel 686', 'Deskripsi untuk produk sampel nomor 686', 1, 6, 1741698.00, 57, 7.17, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(687, 'DUMMY-SKU-0687', 'Produk Sampel 687', 'Deskripsi untuk produk sampel nomor 687', 3, 5, 4966743.00, 26, 17.15, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(688, 'DUMMY-SKU-0688', 'Produk Sampel 688', 'Deskripsi untuk produk sampel nomor 688', 6, 2, 403310.00, 66, 11.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(689, 'DUMMY-SKU-0689', 'Produk Sampel 689', 'Deskripsi untuk produk sampel nomor 689', 2, 5, 654104.00, 97, 19.56, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(690, 'DUMMY-SKU-0690', 'Produk Sampel 690', 'Deskripsi untuk produk sampel nomor 690', 2, 3, 4489684.00, 59, 15.62, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(691, 'DUMMY-SKU-0691', 'Produk Sampel 691', 'Deskripsi untuk produk sampel nomor 691', 3, 5, 1026221.00, 107, 4.97, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(692, 'DUMMY-SKU-0692', 'Produk Sampel 692', 'Deskripsi untuk produk sampel nomor 692', 3, 6, 372414.00, 106, 12.62, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(693, 'DUMMY-SKU-0693', 'Produk Sampel 693', 'Deskripsi untuk produk sampel nomor 693', 2, 2, 2629632.00, 100, 19.01, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(694, 'DUMMY-SKU-0694', 'Produk Sampel 694', 'Deskripsi untuk produk sampel nomor 694', 1, 2, 900366.00, 25, 4.84, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(695, 'DUMMY-SKU-0695', 'Produk Sampel 695', 'Deskripsi untuk produk sampel nomor 695', 6, 7, 1729952.00, 11, 0.72, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(696, 'DUMMY-SKU-0696', 'Produk Sampel 696', 'Deskripsi untuk produk sampel nomor 696', 1, 4, 580145.00, 19, 2.33, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(697, 'DUMMY-SKU-0697', 'Produk Sampel 697', 'Deskripsi untuk produk sampel nomor 697', 2, 1, 3026486.00, 84, 18.01, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(698, 'DUMMY-SKU-0698', 'Produk Sampel 698', 'Deskripsi untuk produk sampel nomor 698', 2, 5, 781313.00, 12, 13.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(699, 'DUMMY-SKU-0699', 'Produk Sampel 699', 'Deskripsi untuk produk sampel nomor 699', 2, 7, 4690097.00, 12, 6.12, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(700, 'DUMMY-SKU-0700', 'Produk Sampel 700', 'Deskripsi untuk produk sampel nomor 700', 4, 3, 724656.00, 93, 15.41, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(701, 'DUMMY-SKU-0701', 'Produk Sampel 701', 'Deskripsi untuk produk sampel nomor 701', 3, 2, 1863784.00, 17, 4.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(702, 'DUMMY-SKU-0702', 'Produk Sampel 702', 'Deskripsi untuk produk sampel nomor 702', 7, 2, 680633.00, 11, 13.27, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(703, 'DUMMY-SKU-0703', 'Produk Sampel 703', 'Deskripsi untuk produk sampel nomor 703', 2, 3, 3724261.00, 90, 16.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(704, 'DUMMY-SKU-0704', 'Produk Sampel 704', 'Deskripsi untuk produk sampel nomor 704', 5, 6, 580728.00, 22, 6.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(705, 'DUMMY-SKU-0705', 'Produk Sampel 705', 'Deskripsi untuk produk sampel nomor 705', 1, 5, 4269330.00, 45, 4.82, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(706, 'DUMMY-SKU-0706', 'Produk Sampel 706', 'Deskripsi untuk produk sampel nomor 706', 1, 6, 3835546.00, 47, 11.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(707, 'DUMMY-SKU-0707', 'Produk Sampel 707', 'Deskripsi untuk produk sampel nomor 707', 6, 3, 2672827.00, 53, 11.52, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(708, 'DUMMY-SKU-0708', 'Produk Sampel 708', 'Deskripsi untuk produk sampel nomor 708', 4, 1, 3071997.00, 99, 13.19, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(709, 'DUMMY-SKU-0709', 'Produk Sampel 709', 'Deskripsi untuk produk sampel nomor 709', 5, 7, 4388869.00, 71, 9.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(710, 'DUMMY-SKU-0710', 'Produk Sampel 710', 'Deskripsi untuk produk sampel nomor 710', 3, 5, 4777212.00, 98, 11.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(711, 'DUMMY-SKU-0711', 'Produk Sampel 711', 'Deskripsi untuk produk sampel nomor 711', 2, 2, 2582034.00, 103, 2.55, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(712, 'DUMMY-SKU-0712', 'Produk Sampel 712', 'Deskripsi untuk produk sampel nomor 712', 6, 5, 328525.00, 31, 17.82, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(713, 'DUMMY-SKU-0713', 'Produk Sampel 713', 'Deskripsi untuk produk sampel nomor 713', 6, 2, 4830925.00, 13, 5.30, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(714, 'DUMMY-SKU-0714', 'Produk Sampel 714', 'Deskripsi untuk produk sampel nomor 714', 2, 2, 3473079.00, 77, 5.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(715, 'DUMMY-SKU-0715', 'Produk Sampel 715', 'Deskripsi untuk produk sampel nomor 715', 3, 1, 1566762.00, 37, 8.72, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(716, 'DUMMY-SKU-0716', 'Produk Sampel 716', 'Deskripsi untuk produk sampel nomor 716', 3, 3, 4706539.00, 62, 16.44, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(717, 'DUMMY-SKU-0717', 'Produk Sampel 717', 'Deskripsi untuk produk sampel nomor 717', 4, 1, 4111442.00, 100, 1.21, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(718, 'DUMMY-SKU-0718', 'Produk Sampel 718', 'Deskripsi untuk produk sampel nomor 718', 4, 5, 3378027.00, 44, 13.72, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(719, 'DUMMY-SKU-0719', 'Produk Sampel 719', 'Deskripsi untuk produk sampel nomor 719', 3, 7, 1199197.00, 65, 1.31, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(720, 'DUMMY-SKU-0720', 'Produk Sampel 720', 'Deskripsi untuk produk sampel nomor 720', 5, 1, 644831.00, 71, 13.52, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(721, 'DUMMY-SKU-0721', 'Produk Sampel 721', 'Deskripsi untuk produk sampel nomor 721', 4, 5, 2410965.00, 66, 8.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(722, 'DUMMY-SKU-0722', 'Produk Sampel 722', 'Deskripsi untuk produk sampel nomor 722', 3, 2, 2169971.00, 47, 11.74, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(723, 'DUMMY-SKU-0723', 'Produk Sampel 723', 'Deskripsi untuk produk sampel nomor 723', 6, 2, 2532292.00, 10, 10.78, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(724, 'DUMMY-SKU-0724', 'Produk Sampel 724', 'Deskripsi untuk produk sampel nomor 724', 5, 5, 517358.00, 79, 3.21, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(725, 'DUMMY-SKU-0725', 'Produk Sampel 725', 'Deskripsi untuk produk sampel nomor 725', 5, 1, 445826.00, 42, 7.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(726, 'DUMMY-SKU-0726', 'Produk Sampel 726', 'Deskripsi untuk produk sampel nomor 726', 6, 6, 4565084.00, 10, 5.98, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(727, 'DUMMY-SKU-0727', 'Produk Sampel 727', 'Deskripsi untuk produk sampel nomor 727', 4, 3, 2853740.00, 78, 14.59, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(728, 'DUMMY-SKU-0728', 'Produk Sampel 728', 'Deskripsi untuk produk sampel nomor 728', 4, 5, 2641112.00, 80, 18.68, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(729, 'DUMMY-SKU-0729', 'Produk Sampel 729', 'Deskripsi untuk produk sampel nomor 729', 4, 7, 4872055.00, 20, 12.16, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(730, 'DUMMY-SKU-0730', 'Produk Sampel 730', 'Deskripsi untuk produk sampel nomor 730', 5, 5, 2181476.00, 14, 18.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(731, 'DUMMY-SKU-0731', 'Produk Sampel 731', 'Deskripsi untuk produk sampel nomor 731', 4, 4, 1457398.00, 95, 7.80, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(732, 'DUMMY-SKU-0732', 'Produk Sampel 732', 'Deskripsi untuk produk sampel nomor 732', 3, 5, 2253024.00, 20, 3.26, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(733, 'DUMMY-SKU-0733', 'Produk Sampel 733', 'Deskripsi untuk produk sampel nomor 733', 4, 7, 1753714.00, 95, 4.94, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(734, 'DUMMY-SKU-0734', 'Produk Sampel 734', 'Deskripsi untuk produk sampel nomor 734', 5, 4, 1933497.00, 64, 11.62, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(735, 'DUMMY-SKU-0735', 'Produk Sampel 735', 'Deskripsi untuk produk sampel nomor 735', 2, 4, 3445565.00, 108, 17.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(736, 'DUMMY-SKU-0736', 'Produk Sampel 736', 'Deskripsi untuk produk sampel nomor 736', 3, 4, 58608.00, 79, 8.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(737, 'DUMMY-SKU-0737', 'Produk Sampel 737', 'Deskripsi untuk produk sampel nomor 737', 1, 3, 1864987.00, 88, 16.22, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(738, 'DUMMY-SKU-0738', 'Produk Sampel 738', 'Deskripsi untuk produk sampel nomor 738', 5, 7, 4304265.00, 45, 4.13, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(739, 'DUMMY-SKU-0739', 'Produk Sampel 739', 'Deskripsi untuk produk sampel nomor 739', 7, 1, 3288922.00, 109, 0.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(740, 'DUMMY-SKU-0740', 'Produk Sampel 740', 'Deskripsi untuk produk sampel nomor 740', 1, 1, 2914293.00, 60, 15.85, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(741, 'DUMMY-SKU-0741', 'Produk Sampel 741', 'Deskripsi untuk produk sampel nomor 741', 3, 6, 2064359.00, 95, 0.77, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(742, 'DUMMY-SKU-0742', 'Produk Sampel 742', 'Deskripsi untuk produk sampel nomor 742', 5, 7, 4446333.00, 70, 7.68, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(743, 'DUMMY-SKU-0743', 'Produk Sampel 743', 'Deskripsi untuk produk sampel nomor 743', 1, 2, 4392322.00, 82, 0.37, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(744, 'DUMMY-SKU-0744', 'Produk Sampel 744', 'Deskripsi untuk produk sampel nomor 744', 7, 3, 905611.00, 90, 9.62, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(745, 'DUMMY-SKU-0745', 'Produk Sampel 745', 'Deskripsi untuk produk sampel nomor 745', 7, 3, 1132411.00, 94, 10.63, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(746, 'DUMMY-SKU-0746', 'Produk Sampel 746', 'Deskripsi untuk produk sampel nomor 746', 1, 7, 2933153.00, 106, 1.94, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(747, 'DUMMY-SKU-0747', 'Produk Sampel 747', 'Deskripsi untuk produk sampel nomor 747', 4, 4, 3914635.00, 54, 17.34, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(748, 'DUMMY-SKU-0748', 'Produk Sampel 748', 'Deskripsi untuk produk sampel nomor 748', 7, 3, 4020402.00, 105, 7.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(749, 'DUMMY-SKU-0749', 'Produk Sampel 749', 'Deskripsi untuk produk sampel nomor 749', 7, 3, 1526401.00, 43, 15.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(750, 'DUMMY-SKU-0750', 'Produk Sampel 750', 'Deskripsi untuk produk sampel nomor 750', 7, 1, 2174381.00, 24, 8.59, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(751, 'DUMMY-SKU-0751', 'Produk Sampel 751', 'Deskripsi untuk produk sampel nomor 751', 5, 2, 3987038.00, 55, 18.27, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(752, 'DUMMY-SKU-0752', 'Produk Sampel 752', 'Deskripsi untuk produk sampel nomor 752', 2, 1, 196379.00, 96, 4.25, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(753, 'DUMMY-SKU-0753', 'Produk Sampel 753', 'Deskripsi untuk produk sampel nomor 753', 4, 5, 3499267.00, 76, 5.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(754, 'DUMMY-SKU-0754', 'Produk Sampel 754', 'Deskripsi untuk produk sampel nomor 754', 2, 3, 1388622.00, 30, 4.26, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(755, 'DUMMY-SKU-0755', 'Produk Sampel 755', 'Deskripsi untuk produk sampel nomor 755', 3, 4, 586295.00, 25, 8.31, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(756, 'DUMMY-SKU-0756', 'Produk Sampel 756', 'Deskripsi untuk produk sampel nomor 756', 5, 6, 40280.00, 84, 14.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(757, 'DUMMY-SKU-0757', 'Produk Sampel 757', 'Deskripsi untuk produk sampel nomor 757', 3, 6, 4634108.00, 24, 18.84, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(758, 'DUMMY-SKU-0758', 'Produk Sampel 758', 'Deskripsi untuk produk sampel nomor 758', 2, 4, 3210907.00, 85, 16.75, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(759, 'DUMMY-SKU-0759', 'Produk Sampel 759', 'Deskripsi untuk produk sampel nomor 759', 7, 1, 2689427.00, 61, 19.93, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(760, 'DUMMY-SKU-0760', 'Produk Sampel 760', 'Deskripsi untuk produk sampel nomor 760', 3, 1, 4344432.00, 39, 18.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(761, 'DUMMY-SKU-0761', 'Produk Sampel 761', 'Deskripsi untuk produk sampel nomor 761', 5, 2, 2196934.00, 56, 0.84, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(762, 'DUMMY-SKU-0762', 'Produk Sampel 762', 'Deskripsi untuk produk sampel nomor 762', 6, 6, 2470675.00, 27, 7.66, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(763, 'DUMMY-SKU-0763', 'Produk Sampel 763', 'Deskripsi untuk produk sampel nomor 763', 3, 6, 3081480.00, 92, 5.78, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(764, 'DUMMY-SKU-0764', 'Produk Sampel 764', 'Deskripsi untuk produk sampel nomor 764', 7, 7, 2498942.00, 99, 19.43, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(765, 'DUMMY-SKU-0765', 'Produk Sampel 765', 'Deskripsi untuk produk sampel nomor 765', 2, 7, 4829579.00, 25, 18.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(766, 'DUMMY-SKU-0766', 'Produk Sampel 766', 'Deskripsi untuk produk sampel nomor 766', 1, 3, 4076763.00, 105, 6.96, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(767, 'DUMMY-SKU-0767', 'Produk Sampel 767', 'Deskripsi untuk produk sampel nomor 767', 6, 2, 2328126.00, 81, 4.00, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(768, 'DUMMY-SKU-0768', 'Produk Sampel 768', 'Deskripsi untuk produk sampel nomor 768', 6, 4, 1022129.00, 50, 8.69, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(769, 'DUMMY-SKU-0769', 'Produk Sampel 769', 'Deskripsi untuk produk sampel nomor 769', 7, 3, 4596083.00, 66, 2.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(770, 'DUMMY-SKU-0770', 'Produk Sampel 770', 'Deskripsi untuk produk sampel nomor 770', 6, 5, 3534731.00, 79, 7.44, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(771, 'DUMMY-SKU-0771', 'Produk Sampel 771', 'Deskripsi untuk produk sampel nomor 771', 6, 5, 4570556.00, 76, 12.37, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(772, 'DUMMY-SKU-0772', 'Produk Sampel 772', 'Deskripsi untuk produk sampel nomor 772', 1, 4, 321219.00, 107, 13.41, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(773, 'DUMMY-SKU-0773', 'Produk Sampel 773', 'Deskripsi untuk produk sampel nomor 773', 3, 1, 842367.00, 68, 8.51, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(774, 'DUMMY-SKU-0774', 'Produk Sampel 774', 'Deskripsi untuk produk sampel nomor 774', 3, 4, 2124860.00, 72, 17.55, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(775, 'DUMMY-SKU-0775', 'Produk Sampel 775', 'Deskripsi untuk produk sampel nomor 775', 4, 6, 2163787.00, 93, 17.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(776, 'DUMMY-SKU-0776', 'Produk Sampel 776', 'Deskripsi untuk produk sampel nomor 776', 7, 6, 2935615.00, 45, 0.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(777, 'DUMMY-SKU-0777', 'Produk Sampel 777', 'Deskripsi untuk produk sampel nomor 777', 1, 1, 1921308.00, 72, 19.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(778, 'DUMMY-SKU-0778', 'Produk Sampel 778', 'Deskripsi untuk produk sampel nomor 778', 1, 3, 3265475.00, 24, 15.22, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(779, 'DUMMY-SKU-0779', 'Produk Sampel 779', 'Deskripsi untuk produk sampel nomor 779', 3, 4, 2387490.00, 95, 16.82, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(780, 'DUMMY-SKU-0780', 'Produk Sampel 780', 'Deskripsi untuk produk sampel nomor 780', 5, 5, 727177.00, 101, 2.67, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(781, 'DUMMY-SKU-0781', 'Produk Sampel 781', 'Deskripsi untuk produk sampel nomor 781', 7, 2, 116166.00, 76, 4.97, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(782, 'DUMMY-SKU-0782', 'Produk Sampel 782', 'Deskripsi untuk produk sampel nomor 782', 2, 4, 2331045.00, 12, 14.66, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(783, 'DUMMY-SKU-0783', 'Produk Sampel 783', 'Deskripsi untuk produk sampel nomor 783', 4, 5, 2752815.00, 89, 6.57, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(784, 'DUMMY-SKU-0784', 'Produk Sampel 784', 'Deskripsi untuk produk sampel nomor 784', 2, 2, 1647728.00, 11, 2.20, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(785, 'DUMMY-SKU-0785', 'Produk Sampel 785', 'Deskripsi untuk produk sampel nomor 785', 4, 1, 4155312.00, 109, 10.00, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(786, 'DUMMY-SKU-0786', 'Produk Sampel 786', 'Deskripsi untuk produk sampel nomor 786', 4, 7, 1377720.00, 62, 16.49, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(787, 'DUMMY-SKU-0787', 'Produk Sampel 787', 'Deskripsi untuk produk sampel nomor 787', 4, 1, 86999.00, 84, 13.41, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(788, 'DUMMY-SKU-0788', 'Produk Sampel 788', 'Deskripsi untuk produk sampel nomor 788', 1, 4, 1227875.00, 78, 14.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(789, 'DUMMY-SKU-0789', 'Produk Sampel 789', 'Deskripsi untuk produk sampel nomor 789', 4, 3, 2664761.00, 51, 9.63, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(790, 'DUMMY-SKU-0790', 'Produk Sampel 790', 'Deskripsi untuk produk sampel nomor 790', 1, 2, 4839431.00, 109, 1.64, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(791, 'DUMMY-SKU-0791', 'Produk Sampel 791', 'Deskripsi untuk produk sampel nomor 791', 3, 6, 3313754.00, 108, 19.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(792, 'DUMMY-SKU-0792', 'Produk Sampel 792', 'Deskripsi untuk produk sampel nomor 792', 6, 1, 4495172.00, 44, 1.05, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(793, 'DUMMY-SKU-0793', 'Produk Sampel 793', 'Deskripsi untuk produk sampel nomor 793', 2, 6, 2826607.00, 42, 19.18, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(794, 'DUMMY-SKU-0794', 'Produk Sampel 794', 'Deskripsi untuk produk sampel nomor 794', 6, 1, 4608102.00, 53, 8.60, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(795, 'DUMMY-SKU-0795', 'Produk Sampel 795', 'Deskripsi untuk produk sampel nomor 795', 6, 6, 2775492.00, 46, 3.59, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(796, 'DUMMY-SKU-0796', 'Produk Sampel 796', 'Deskripsi untuk produk sampel nomor 796', 6, 3, 1772438.00, 86, 15.23, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(797, 'DUMMY-SKU-0797', 'Produk Sampel 797', 'Deskripsi untuk produk sampel nomor 797', 4, 2, 2591283.00, 108, 7.40, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(798, 'DUMMY-SKU-0798', 'Produk Sampel 798', 'Deskripsi untuk produk sampel nomor 798', 7, 3, 4130670.00, 34, 15.35, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(799, 'DUMMY-SKU-0799', 'Produk Sampel 799', 'Deskripsi untuk produk sampel nomor 799', 1, 1, 746306.00, 61, 3.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(800, 'DUMMY-SKU-0800', 'Produk Sampel 800', 'Deskripsi untuk produk sampel nomor 800', 2, 4, 4739331.00, 31, 5.34, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(801, 'DUMMY-SKU-0801', 'Produk Sampel 801', 'Deskripsi untuk produk sampel nomor 801', 5, 4, 1851405.00, 55, 3.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(802, 'DUMMY-SKU-0802', 'Produk Sampel 802', 'Deskripsi untuk produk sampel nomor 802', 3, 4, 1855290.00, 42, 10.00, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(803, 'DUMMY-SKU-0803', 'Produk Sampel 803', 'Deskripsi untuk produk sampel nomor 803', 4, 1, 4351474.00, 19, 17.66, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(804, 'DUMMY-SKU-0804', 'Produk Sampel 804', 'Deskripsi untuk produk sampel nomor 804', 1, 7, 279294.00, 75, 2.34, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(805, 'DUMMY-SKU-0805', 'Produk Sampel 805', 'Deskripsi untuk produk sampel nomor 805', 5, 5, 2240346.00, 38, 2.19, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(806, 'DUMMY-SKU-0806', 'Produk Sampel 806', 'Deskripsi untuk produk sampel nomor 806', 5, 7, 4332817.00, 52, 10.58, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(807, 'DUMMY-SKU-0807', 'Produk Sampel 807', 'Deskripsi untuk produk sampel nomor 807', 3, 2, 4190949.00, 74, 14.87, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(808, 'DUMMY-SKU-0808', 'Produk Sampel 808', 'Deskripsi untuk produk sampel nomor 808', 6, 4, 1465487.00, 104, 16.80, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(809, 'DUMMY-SKU-0809', 'Produk Sampel 809', 'Deskripsi untuk produk sampel nomor 809', 3, 2, 882263.00, 23, 3.40, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(810, 'DUMMY-SKU-0810', 'Produk Sampel 810', 'Deskripsi untuk produk sampel nomor 810', 3, 4, 2915409.00, 31, 6.83, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(811, 'DUMMY-SKU-0811', 'Produk Sampel 811', 'Deskripsi untuk produk sampel nomor 811', 1, 2, 3528356.00, 13, 1.37, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(812, 'DUMMY-SKU-0812', 'Produk Sampel 812', 'Deskripsi untuk produk sampel nomor 812', 2, 7, 3571188.00, 105, 12.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(813, 'DUMMY-SKU-0813', 'Produk Sampel 813', 'Deskripsi untuk produk sampel nomor 813', 2, 4, 2801738.00, 47, 3.67, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(814, 'DUMMY-SKU-0814', 'Produk Sampel 814', 'Deskripsi untuk produk sampel nomor 814', 6, 3, 2454663.00, 44, 5.44, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(815, 'DUMMY-SKU-0815', 'Produk Sampel 815', 'Deskripsi untuk produk sampel nomor 815', 3, 5, 2495725.00, 55, 15.79, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(816, 'DUMMY-SKU-0816', 'Produk Sampel 816', 'Deskripsi untuk produk sampel nomor 816', 4, 4, 2401273.00, 20, 1.65, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(817, 'DUMMY-SKU-0817', 'Produk Sampel 817', 'Deskripsi untuk produk sampel nomor 817', 1, 2, 3106042.00, 67, 0.79, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(818, 'DUMMY-SKU-0818', 'Produk Sampel 818', 'Deskripsi untuk produk sampel nomor 818', 4, 1, 593275.00, 42, 5.58, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(819, 'DUMMY-SKU-0819', 'Produk Sampel 819', 'Deskripsi untuk produk sampel nomor 819', 3, 2, 3002093.00, 62, 16.24, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(820, 'DUMMY-SKU-0820', 'Produk Sampel 820', 'Deskripsi untuk produk sampel nomor 820', 4, 7, 1611096.00, 85, 16.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(821, 'DUMMY-SKU-0821', 'Produk Sampel 821', 'Deskripsi untuk produk sampel nomor 821', 6, 5, 4548004.00, 60, 16.15, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(822, 'DUMMY-SKU-0822', 'Produk Sampel 822', 'Deskripsi untuk produk sampel nomor 822', 4, 1, 4499521.00, 35, 11.84, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(823, 'DUMMY-SKU-0823', 'Produk Sampel 823', 'Deskripsi untuk produk sampel nomor 823', 2, 1, 4318096.00, 19, 17.51, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(824, 'DUMMY-SKU-0824', 'Produk Sampel 824', 'Deskripsi untuk produk sampel nomor 824', 1, 6, 3498845.00, 22, 10.87, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(825, 'DUMMY-SKU-0825', 'Produk Sampel 825', 'Deskripsi untuk produk sampel nomor 825', 3, 7, 4188712.00, 41, 1.09, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(826, 'DUMMY-SKU-0826', 'Produk Sampel 826', 'Deskripsi untuk produk sampel nomor 826', 3, 3, 820781.00, 64, 5.21, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(827, 'DUMMY-SKU-0827', 'Produk Sampel 827', 'Deskripsi untuk produk sampel nomor 827', 5, 3, 485515.00, 37, 2.26, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(828, 'DUMMY-SKU-0828', 'Produk Sampel 828', 'Deskripsi untuk produk sampel nomor 828', 5, 2, 4375512.00, 87, 5.11, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(829, 'DUMMY-SKU-0829', 'Produk Sampel 829', 'Deskripsi untuk produk sampel nomor 829', 7, 7, 3589699.00, 97, 4.65, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(830, 'DUMMY-SKU-0830', 'Produk Sampel 830', 'Deskripsi untuk produk sampel nomor 830', 4, 7, 4246647.00, 70, 9.98, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(831, 'DUMMY-SKU-0831', 'Produk Sampel 831', 'Deskripsi untuk produk sampel nomor 831', 5, 6, 4197463.00, 101, 1.80, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(832, 'DUMMY-SKU-0832', 'Produk Sampel 832', 'Deskripsi untuk produk sampel nomor 832', 5, 1, 2013638.00, 86, 12.28, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(833, 'DUMMY-SKU-0833', 'Produk Sampel 833', 'Deskripsi untuk produk sampel nomor 833', 6, 7, 2822883.00, 100, 17.24, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(834, 'DUMMY-SKU-0834', 'Produk Sampel 834', 'Deskripsi untuk produk sampel nomor 834', 4, 2, 2128954.00, 56, 0.68, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(835, 'DUMMY-SKU-0835', 'Produk Sampel 835', 'Deskripsi untuk produk sampel nomor 835', 6, 6, 1937160.00, 81, 8.95, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(836, 'DUMMY-SKU-0836', 'Produk Sampel 836', 'Deskripsi untuk produk sampel nomor 836', 1, 7, 2665708.00, 94, 12.38, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(837, 'DUMMY-SKU-0837', 'Produk Sampel 837', 'Deskripsi untuk produk sampel nomor 837', 4, 7, 3879981.00, 32, 16.19, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(838, 'DUMMY-SKU-0838', 'Produk Sampel 838', 'Deskripsi untuk produk sampel nomor 838', 3, 3, 2895173.00, 101, 16.80, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(839, 'DUMMY-SKU-0839', 'Produk Sampel 839', 'Deskripsi untuk produk sampel nomor 839', 4, 5, 234526.00, 31, 18.88, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(840, 'DUMMY-SKU-0840', 'Produk Sampel 840', 'Deskripsi untuk produk sampel nomor 840', 1, 4, 88355.00, 87, 17.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(841, 'DUMMY-SKU-0841', 'Produk Sampel 841', 'Deskripsi untuk produk sampel nomor 841', 7, 7, 1024677.00, 16, 14.12, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(842, 'DUMMY-SKU-0842', 'Produk Sampel 842', 'Deskripsi untuk produk sampel nomor 842', 3, 4, 2617923.00, 21, 0.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(843, 'DUMMY-SKU-0843', 'Produk Sampel 843', 'Deskripsi untuk produk sampel nomor 843', 6, 7, 130655.00, 57, 6.26, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(844, 'DUMMY-SKU-0844', 'Produk Sampel 844', 'Deskripsi untuk produk sampel nomor 844', 1, 5, 4250886.00, 42, 2.20, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(845, 'DUMMY-SKU-0845', 'Produk Sampel 845', 'Deskripsi untuk produk sampel nomor 845', 4, 3, 997933.00, 100, 18.87, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(846, 'DUMMY-SKU-0846', 'Produk Sampel 846', 'Deskripsi untuk produk sampel nomor 846', 7, 1, 1675556.00, 61, 11.52, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(847, 'DUMMY-SKU-0847', 'Produk Sampel 847', 'Deskripsi untuk produk sampel nomor 847', 3, 6, 1637968.00, 16, 7.43, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(848, 'DUMMY-SKU-0848', 'Produk Sampel 848', 'Deskripsi untuk produk sampel nomor 848', 5, 1, 1532516.00, 51, 2.86, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(849, 'DUMMY-SKU-0849', 'Produk Sampel 849', 'Deskripsi untuk produk sampel nomor 849', 4, 7, 125020.00, 57, 6.27, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(850, 'DUMMY-SKU-0850', 'Produk Sampel 850', 'Deskripsi untuk produk sampel nomor 850', 1, 5, 4693462.00, 81, 15.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(851, 'DUMMY-SKU-0851', 'Produk Sampel 851', 'Deskripsi untuk produk sampel nomor 851', 5, 6, 166823.00, 95, 3.69, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(852, 'DUMMY-SKU-0852', 'Produk Sampel 852', 'Deskripsi untuk produk sampel nomor 852', 3, 1, 3242584.00, 94, 5.72, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(853, 'DUMMY-SKU-0853', 'Produk Sampel 853', 'Deskripsi untuk produk sampel nomor 853', 7, 4, 4964236.00, 48, 19.47, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(854, 'DUMMY-SKU-0854', 'Produk Sampel 854', 'Deskripsi untuk produk sampel nomor 854', 5, 4, 1990837.00, 62, 8.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(855, 'DUMMY-SKU-0855', 'Produk Sampel 855', 'Deskripsi untuk produk sampel nomor 855', 4, 4, 2864793.00, 63, 19.78, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(856, 'DUMMY-SKU-0856', 'Produk Sampel 856', 'Deskripsi untuk produk sampel nomor 856', 3, 4, 4487254.00, 89, 5.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(857, 'DUMMY-SKU-0857', 'Produk Sampel 857', 'Deskripsi untuk produk sampel nomor 857', 1, 4, 245312.00, 99, 6.58, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(858, 'DUMMY-SKU-0858', 'Produk Sampel 858', 'Deskripsi untuk produk sampel nomor 858', 7, 6, 4122090.00, 102, 3.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(859, 'DUMMY-SKU-0859', 'Produk Sampel 859', 'Deskripsi untuk produk sampel nomor 859', 1, 6, 3162275.00, 98, 10.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(860, 'DUMMY-SKU-0860', 'Produk Sampel 860', 'Deskripsi untuk produk sampel nomor 860', 7, 2, 378133.00, 91, 17.44, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(861, 'DUMMY-SKU-0861', 'Produk Sampel 861', 'Deskripsi untuk produk sampel nomor 861', 7, 6, 2002870.00, 66, 12.81, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(862, 'DUMMY-SKU-0862', 'Produk Sampel 862', 'Deskripsi untuk produk sampel nomor 862', 4, 4, 36673.00, 66, 15.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(863, 'DUMMY-SKU-0863', 'Produk Sampel 863', 'Deskripsi untuk produk sampel nomor 863', 2, 7, 85709.00, 28, 17.86, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(864, 'DUMMY-SKU-0864', 'Produk Sampel 864', 'Deskripsi untuk produk sampel nomor 864', 7, 6, 199481.00, 108, 16.12, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(865, 'DUMMY-SKU-0865', 'Produk Sampel 865', 'Deskripsi untuk produk sampel nomor 865', 1, 7, 1097392.00, 55, 12.66, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(866, 'DUMMY-SKU-0866', 'Produk Sampel 866', 'Deskripsi untuk produk sampel nomor 866', 6, 7, 2869298.00, 102, 18.36, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(867, 'DUMMY-SKU-0867', 'Produk Sampel 867', 'Deskripsi untuk produk sampel nomor 867', 6, 2, 3237992.00, 72, 3.54, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(868, 'DUMMY-SKU-0868', 'Produk Sampel 868', 'Deskripsi untuk produk sampel nomor 868', 7, 4, 1489014.00, 21, 13.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(869, 'DUMMY-SKU-0869', 'Produk Sampel 869', 'Deskripsi untuk produk sampel nomor 869', 1, 1, 2153704.00, 94, 18.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(870, 'DUMMY-SKU-0870', 'Produk Sampel 870', 'Deskripsi untuk produk sampel nomor 870', 2, 1, 2572685.00, 65, 5.31, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24');
INSERT INTO `products` (`id`, `sku`, `name`, `description`, `category_id`, `supplier_id`, `unit_price`, `minimum_stock`, `weight`, `status`, `created_at`, `updated_at`) VALUES
(871, 'DUMMY-SKU-0871', 'Produk Sampel 871', 'Deskripsi untuk produk sampel nomor 871', 5, 3, 4050785.00, 13, 14.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(872, 'DUMMY-SKU-0872', 'Produk Sampel 872', 'Deskripsi untuk produk sampel nomor 872', 5, 7, 2435750.00, 91, 12.77, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(873, 'DUMMY-SKU-0873', 'Produk Sampel 873', 'Deskripsi untuk produk sampel nomor 873', 6, 5, 1081257.00, 15, 12.92, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(874, 'DUMMY-SKU-0874', 'Produk Sampel 874', 'Deskripsi untuk produk sampel nomor 874', 1, 2, 656532.00, 100, 3.18, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(875, 'DUMMY-SKU-0875', 'Produk Sampel 875', 'Deskripsi untuk produk sampel nomor 875', 1, 6, 3329057.00, 14, 4.40, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(876, 'DUMMY-SKU-0876', 'Produk Sampel 876', 'Deskripsi untuk produk sampel nomor 876', 7, 1, 3512351.00, 26, 15.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(877, 'DUMMY-SKU-0877', 'Produk Sampel 877', 'Deskripsi untuk produk sampel nomor 877', 2, 7, 4447651.00, 78, 15.51, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(878, 'DUMMY-SKU-0878', 'Produk Sampel 878', 'Deskripsi untuk produk sampel nomor 878', 6, 5, 4473536.00, 59, 16.54, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(879, 'DUMMY-SKU-0879', 'Produk Sampel 879', 'Deskripsi untuk produk sampel nomor 879', 5, 5, 377099.00, 72, 18.36, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(880, 'DUMMY-SKU-0880', 'Produk Sampel 880', 'Deskripsi untuk produk sampel nomor 880', 5, 5, 1841657.00, 87, 16.09, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(881, 'DUMMY-SKU-0881', 'Produk Sampel 881', 'Deskripsi untuk produk sampel nomor 881', 5, 7, 2498805.00, 90, 10.68, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(882, 'DUMMY-SKU-0882', 'Produk Sampel 882', 'Deskripsi untuk produk sampel nomor 882', 2, 5, 905422.00, 26, 6.28, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(883, 'DUMMY-SKU-0883', 'Produk Sampel 883', 'Deskripsi untuk produk sampel nomor 883', 1, 2, 977402.00, 28, 6.83, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(884, 'DUMMY-SKU-0884', 'Produk Sampel 884', 'Deskripsi untuk produk sampel nomor 884', 1, 5, 4340722.00, 47, 5.39, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(885, 'DUMMY-SKU-0885', 'Produk Sampel 885', 'Deskripsi untuk produk sampel nomor 885', 2, 2, 2746776.00, 13, 11.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(886, 'DUMMY-SKU-0886', 'Produk Sampel 886', 'Deskripsi untuk produk sampel nomor 886', 5, 4, 4389692.00, 79, 17.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(887, 'DUMMY-SKU-0887', 'Produk Sampel 887', 'Deskripsi untuk produk sampel nomor 887', 2, 3, 19602.00, 19, 9.89, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(888, 'DUMMY-SKU-0888', 'Produk Sampel 888', 'Deskripsi untuk produk sampel nomor 888', 2, 3, 4907790.00, 13, 5.13, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(889, 'DUMMY-SKU-0889', 'Produk Sampel 889', 'Deskripsi untuk produk sampel nomor 889', 2, 7, 1917164.00, 12, 19.24, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(890, 'DUMMY-SKU-0890', 'Produk Sampel 890', 'Deskripsi untuk produk sampel nomor 890', 6, 6, 2914423.00, 75, 10.45, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(891, 'DUMMY-SKU-0891', 'Produk Sampel 891', 'Deskripsi untuk produk sampel nomor 891', 5, 5, 593340.00, 87, 10.89, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(892, 'DUMMY-SKU-0892', 'Produk Sampel 892', 'Deskripsi untuk produk sampel nomor 892', 3, 2, 4662552.00, 13, 8.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(893, 'DUMMY-SKU-0893', 'Produk Sampel 893', 'Deskripsi untuk produk sampel nomor 893', 7, 2, 772870.00, 40, 1.85, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(894, 'DUMMY-SKU-0894', 'Produk Sampel 894', 'Deskripsi untuk produk sampel nomor 894', 4, 3, 4672850.00, 88, 2.45, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(895, 'DUMMY-SKU-0895', 'Produk Sampel 895', 'Deskripsi untuk produk sampel nomor 895', 2, 6, 2336633.00, 91, 14.18, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(896, 'DUMMY-SKU-0896', 'Produk Sampel 896', 'Deskripsi untuk produk sampel nomor 896', 1, 2, 3721722.00, 26, 11.56, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(897, 'DUMMY-SKU-0897', 'Produk Sampel 897', 'Deskripsi untuk produk sampel nomor 897', 3, 2, 4428291.00, 89, 6.51, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(898, 'DUMMY-SKU-0898', 'Produk Sampel 898', 'Deskripsi untuk produk sampel nomor 898', 2, 1, 40704.00, 73, 3.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(899, 'DUMMY-SKU-0899', 'Produk Sampel 899', 'Deskripsi untuk produk sampel nomor 899', 6, 6, 1653439.00, 42, 13.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(900, 'DUMMY-SKU-0900', 'Produk Sampel 900', 'Deskripsi untuk produk sampel nomor 900', 2, 4, 1622246.00, 41, 12.69, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(901, 'DUMMY-SKU-0901', 'Produk Sampel 901', 'Deskripsi untuk produk sampel nomor 901', 2, 1, 3717414.00, 61, 7.60, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(902, 'DUMMY-SKU-0902', 'Produk Sampel 902', 'Deskripsi untuk produk sampel nomor 902', 3, 4, 1670331.00, 39, 9.33, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(903, 'DUMMY-SKU-0903', 'Produk Sampel 903', 'Deskripsi untuk produk sampel nomor 903', 4, 6, 3096730.00, 83, 16.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(904, 'DUMMY-SKU-0904', 'Produk Sampel 904', 'Deskripsi untuk produk sampel nomor 904', 7, 1, 4476502.00, 17, 13.64, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(905, 'DUMMY-SKU-0905', 'Produk Sampel 905', 'Deskripsi untuk produk sampel nomor 905', 2, 6, 3024839.00, 64, 18.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(906, 'DUMMY-SKU-0906', 'Produk Sampel 906', 'Deskripsi untuk produk sampel nomor 906', 7, 1, 1537543.00, 51, 3.62, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(907, 'DUMMY-SKU-0907', 'Produk Sampel 907', 'Deskripsi untuk produk sampel nomor 907', 5, 5, 530869.00, 83, 7.23, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(908, 'DUMMY-SKU-0908', 'Produk Sampel 908', 'Deskripsi untuk produk sampel nomor 908', 5, 6, 2098548.00, 69, 14.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(909, 'DUMMY-SKU-0909', 'Produk Sampel 909', 'Deskripsi untuk produk sampel nomor 909', 6, 6, 4046817.00, 61, 3.36, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(910, 'DUMMY-SKU-0910', 'Produk Sampel 910', 'Deskripsi untuk produk sampel nomor 910', 2, 6, 1798627.00, 39, 8.56, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(911, 'DUMMY-SKU-0911', 'Produk Sampel 911', 'Deskripsi untuk produk sampel nomor 911', 2, 6, 2287710.00, 91, 13.90, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(912, 'DUMMY-SKU-0912', 'Produk Sampel 912', 'Deskripsi untuk produk sampel nomor 912', 1, 1, 4996685.00, 105, 16.25, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(913, 'DUMMY-SKU-0913', 'Produk Sampel 913', 'Deskripsi untuk produk sampel nomor 913', 2, 3, 1886366.00, 86, 14.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(914, 'DUMMY-SKU-0914', 'Produk Sampel 914', 'Deskripsi untuk produk sampel nomor 914', 2, 7, 885483.00, 108, 8.12, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(915, 'DUMMY-SKU-0915', 'Produk Sampel 915', 'Deskripsi untuk produk sampel nomor 915', 1, 1, 389977.00, 34, 20.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(916, 'DUMMY-SKU-0916', 'Produk Sampel 916', 'Deskripsi untuk produk sampel nomor 916', 2, 2, 2734700.00, 104, 2.18, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(917, 'DUMMY-SKU-0917', 'Produk Sampel 917', 'Deskripsi untuk produk sampel nomor 917', 5, 1, 1608467.00, 48, 19.85, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(918, 'DUMMY-SKU-0918', 'Produk Sampel 918', 'Deskripsi untuk produk sampel nomor 918', 6, 7, 647496.00, 107, 9.93, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(919, 'DUMMY-SKU-0919', 'Produk Sampel 919', 'Deskripsi untuk produk sampel nomor 919', 4, 2, 1888473.00, 39, 6.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(920, 'DUMMY-SKU-0920', 'Produk Sampel 920', 'Deskripsi untuk produk sampel nomor 920', 6, 7, 846630.00, 23, 3.56, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(921, 'DUMMY-SKU-0921', 'Produk Sampel 921', 'Deskripsi untuk produk sampel nomor 921', 4, 6, 2571081.00, 32, 12.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(922, 'DUMMY-SKU-0922', 'Produk Sampel 922', 'Deskripsi untuk produk sampel nomor 922', 3, 6, 4303382.00, 11, 10.49, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(923, 'DUMMY-SKU-0923', 'Produk Sampel 923', 'Deskripsi untuk produk sampel nomor 923', 4, 1, 405998.00, 107, 13.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(924, 'DUMMY-SKU-0924', 'Produk Sampel 924', 'Deskripsi untuk produk sampel nomor 924', 3, 5, 815478.00, 104, 4.88, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(925, 'DUMMY-SKU-0925', 'Produk Sampel 925', 'Deskripsi untuk produk sampel nomor 925', 3, 1, 1863056.00, 67, 15.84, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(926, 'DUMMY-SKU-0926', 'Produk Sampel 926', 'Deskripsi untuk produk sampel nomor 926', 2, 5, 2536026.00, 77, 16.81, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(927, 'DUMMY-SKU-0927', 'Produk Sampel 927', 'Deskripsi untuk produk sampel nomor 927', 2, 3, 605786.00, 72, 15.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(928, 'DUMMY-SKU-0928', 'Produk Sampel 928', 'Deskripsi untuk produk sampel nomor 928', 7, 5, 4969874.00, 30, 0.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(929, 'DUMMY-SKU-0929', 'Produk Sampel 929', 'Deskripsi untuk produk sampel nomor 929', 4, 4, 1049077.00, 46, 4.23, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(930, 'DUMMY-SKU-0930', 'Produk Sampel 930', 'Deskripsi untuk produk sampel nomor 930', 7, 1, 2399241.00, 31, 13.32, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(931, 'DUMMY-SKU-0931', 'Produk Sampel 931', 'Deskripsi untuk produk sampel nomor 931', 5, 2, 1644798.00, 97, 7.85, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(932, 'DUMMY-SKU-0932', 'Produk Sampel 932', 'Deskripsi untuk produk sampel nomor 932', 3, 3, 751071.00, 58, 19.47, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(933, 'DUMMY-SKU-0933', 'Produk Sampel 933', 'Deskripsi untuk produk sampel nomor 933', 3, 1, 834191.00, 71, 11.60, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(934, 'DUMMY-SKU-0934', 'Produk Sampel 934', 'Deskripsi untuk produk sampel nomor 934', 1, 4, 612276.00, 36, 19.75, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(935, 'DUMMY-SKU-0935', 'Produk Sampel 935', 'Deskripsi untuk produk sampel nomor 935', 1, 5, 3089026.00, 41, 14.83, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(936, 'DUMMY-SKU-0936', 'Produk Sampel 936', 'Deskripsi untuk produk sampel nomor 936', 6, 4, 220951.00, 96, 4.52, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(937, 'DUMMY-SKU-0937', 'Produk Sampel 937', 'Deskripsi untuk produk sampel nomor 937', 4, 6, 2959405.00, 60, 15.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(938, 'DUMMY-SKU-0938', 'Produk Sampel 938', 'Deskripsi untuk produk sampel nomor 938', 2, 7, 4122105.00, 50, 11.37, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(939, 'DUMMY-SKU-0939', 'Produk Sampel 939', 'Deskripsi untuk produk sampel nomor 939', 5, 3, 3658938.00, 83, 9.56, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(940, 'DUMMY-SKU-0940', 'Produk Sampel 940', 'Deskripsi untuk produk sampel nomor 940', 2, 3, 2951796.00, 78, 13.55, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(941, 'DUMMY-SKU-0941', 'Produk Sampel 941', 'Deskripsi untuk produk sampel nomor 941', 3, 4, 2466859.00, 12, 13.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(942, 'DUMMY-SKU-0942', 'Produk Sampel 942', 'Deskripsi untuk produk sampel nomor 942', 2, 6, 4020283.00, 54, 16.28, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(943, 'DUMMY-SKU-0943', 'Produk Sampel 943', 'Deskripsi untuk produk sampel nomor 943', 6, 2, 3160524.00, 78, 10.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(944, 'DUMMY-SKU-0944', 'Produk Sampel 944', 'Deskripsi untuk produk sampel nomor 944', 4, 2, 2534067.00, 91, 11.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(945, 'DUMMY-SKU-0945', 'Produk Sampel 945', 'Deskripsi untuk produk sampel nomor 945', 3, 7, 2432461.00, 88, 9.28, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(946, 'DUMMY-SKU-0946', 'Produk Sampel 946', 'Deskripsi untuk produk sampel nomor 946', 7, 3, 4792416.00, 80, 13.05, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(947, 'DUMMY-SKU-0947', 'Produk Sampel 947', 'Deskripsi untuk produk sampel nomor 947', 1, 5, 415330.00, 42, 8.06, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(948, 'DUMMY-SKU-0948', 'Produk Sampel 948', 'Deskripsi untuk produk sampel nomor 948', 1, 6, 745148.00, 33, 15.01, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(949, 'DUMMY-SKU-0949', 'Produk Sampel 949', 'Deskripsi untuk produk sampel nomor 949', 1, 6, 858673.00, 41, 1.70, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(950, 'DUMMY-SKU-0950', 'Produk Sampel 950', 'Deskripsi untuk produk sampel nomor 950', 4, 7, 3161888.00, 26, 19.20, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(951, 'DUMMY-SKU-0951', 'Produk Sampel 951', 'Deskripsi untuk produk sampel nomor 951', 2, 4, 2817576.00, 48, 5.31, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(952, 'DUMMY-SKU-0952', 'Produk Sampel 952', 'Deskripsi untuk produk sampel nomor 952', 1, 7, 275286.00, 69, 16.07, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(953, 'DUMMY-SKU-0953', 'Produk Sampel 953', 'Deskripsi untuk produk sampel nomor 953', 2, 5, 4066044.00, 107, 9.19, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(954, 'DUMMY-SKU-0954', 'Produk Sampel 954', 'Deskripsi untuk produk sampel nomor 954', 3, 3, 3210857.00, 30, 2.37, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(955, 'DUMMY-SKU-0955', 'Produk Sampel 955', 'Deskripsi untuk produk sampel nomor 955', 7, 3, 655058.00, 56, 18.69, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(956, 'DUMMY-SKU-0956', 'Produk Sampel 956', 'Deskripsi untuk produk sampel nomor 956', 2, 4, 3662384.00, 24, 11.26, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(957, 'DUMMY-SKU-0957', 'Produk Sampel 957', 'Deskripsi untuk produk sampel nomor 957', 3, 1, 527244.00, 54, 18.29, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(958, 'DUMMY-SKU-0958', 'Produk Sampel 958', 'Deskripsi untuk produk sampel nomor 958', 2, 3, 416372.00, 47, 12.36, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(959, 'DUMMY-SKU-0959', 'Produk Sampel 959', 'Deskripsi untuk produk sampel nomor 959', 7, 7, 3718854.00, 105, 10.65, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(960, 'DUMMY-SKU-0960', 'Produk Sampel 960', 'Deskripsi untuk produk sampel nomor 960', 6, 3, 1821633.00, 88, 16.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(961, 'DUMMY-SKU-0961', 'Produk Sampel 961', 'Deskripsi untuk produk sampel nomor 961', 6, 2, 917185.00, 15, 14.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(962, 'DUMMY-SKU-0962', 'Produk Sampel 962', 'Deskripsi untuk produk sampel nomor 962', 3, 7, 2880783.00, 106, 2.09, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(963, 'DUMMY-SKU-0963', 'Produk Sampel 963', 'Deskripsi untuk produk sampel nomor 963', 5, 6, 3968728.00, 89, 12.29, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(964, 'DUMMY-SKU-0964', 'Produk Sampel 964', 'Deskripsi untuk produk sampel nomor 964', 5, 4, 1533379.00, 25, 17.67, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(965, 'DUMMY-SKU-0965', 'Produk Sampel 965', 'Deskripsi untuk produk sampel nomor 965', 7, 7, 23656.00, 26, 16.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(966, 'DUMMY-SKU-0966', 'Produk Sampel 966', 'Deskripsi untuk produk sampel nomor 966', 4, 1, 4970942.00, 77, 7.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(967, 'DUMMY-SKU-0967', 'Produk Sampel 967', 'Deskripsi untuk produk sampel nomor 967', 7, 3, 4080816.00, 28, 9.79, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(968, 'DUMMY-SKU-0968', 'Produk Sampel 968', 'Deskripsi untuk produk sampel nomor 968', 7, 7, 3954802.00, 41, 3.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(969, 'DUMMY-SKU-0969', 'Produk Sampel 969', 'Deskripsi untuk produk sampel nomor 969', 1, 5, 4384644.00, 68, 6.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(970, 'DUMMY-SKU-0970', 'Produk Sampel 970', 'Deskripsi untuk produk sampel nomor 970', 6, 6, 4023663.00, 69, 11.89, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(971, 'DUMMY-SKU-0971', 'Produk Sampel 971', 'Deskripsi untuk produk sampel nomor 971', 2, 7, 2124290.00, 29, 14.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(972, 'DUMMY-SKU-0972', 'Produk Sampel 972', 'Deskripsi untuk produk sampel nomor 972', 7, 4, 3267442.00, 91, 2.88, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(973, 'DUMMY-SKU-0973', 'Produk Sampel 973', 'Deskripsi untuk produk sampel nomor 973', 2, 6, 965089.00, 70, 9.49, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(974, 'DUMMY-SKU-0974', 'Produk Sampel 974', 'Deskripsi untuk produk sampel nomor 974', 4, 2, 2207398.00, 69, 13.16, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(975, 'DUMMY-SKU-0975', 'Produk Sampel 975', 'Deskripsi untuk produk sampel nomor 975', 4, 4, 4085321.00, 81, 3.01, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(976, 'DUMMY-SKU-0976', 'Produk Sampel 976', 'Deskripsi untuk produk sampel nomor 976', 5, 4, 2140816.00, 94, 18.88, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(977, 'DUMMY-SKU-0977', 'Produk Sampel 977', 'Deskripsi untuk produk sampel nomor 977', 2, 1, 2660144.00, 73, 11.94, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(978, 'DUMMY-SKU-0978', 'Produk Sampel 978', 'Deskripsi untuk produk sampel nomor 978', 1, 4, 1184447.00, 84, 0.24, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(979, 'DUMMY-SKU-0979', 'Produk Sampel 979', 'Deskripsi untuk produk sampel nomor 979', 6, 1, 3334533.00, 37, 7.38, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(980, 'DUMMY-SKU-0980', 'Produk Sampel 980', 'Deskripsi untuk produk sampel nomor 980', 1, 7, 3306065.00, 59, 9.60, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(981, 'DUMMY-SKU-0981', 'Produk Sampel 981', 'Deskripsi untuk produk sampel nomor 981', 7, 1, 3843809.00, 64, 8.69, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(982, 'DUMMY-SKU-0982', 'Produk Sampel 982', 'Deskripsi untuk produk sampel nomor 982', 4, 2, 3935187.00, 23, 6.53, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(983, 'DUMMY-SKU-0983', 'Produk Sampel 983', 'Deskripsi untuk produk sampel nomor 983', 2, 1, 3045752.00, 100, 14.58, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(984, 'DUMMY-SKU-0984', 'Produk Sampel 984', 'Deskripsi untuk produk sampel nomor 984', 7, 3, 3923655.00, 13, 16.82, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(985, 'DUMMY-SKU-0985', 'Produk Sampel 985', 'Deskripsi untuk produk sampel nomor 985', 1, 6, 4963218.00, 53, 4.02, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(986, 'DUMMY-SKU-0986', 'Produk Sampel 986', 'Deskripsi untuk produk sampel nomor 986', 5, 6, 4989347.00, 65, 16.34, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(987, 'DUMMY-SKU-0987', 'Produk Sampel 987', 'Deskripsi untuk produk sampel nomor 987', 3, 4, 914985.00, 61, 0.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(988, 'DUMMY-SKU-0988', 'Produk Sampel 988', 'Deskripsi untuk produk sampel nomor 988', 4, 6, 4882119.00, 78, 10.10, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(989, 'DUMMY-SKU-0989', 'Produk Sampel 989', 'Deskripsi untuk produk sampel nomor 989', 4, 6, 1474959.00, 38, 11.34, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(990, 'DUMMY-SKU-0990', 'Produk Sampel 990', 'Deskripsi untuk produk sampel nomor 990', 7, 1, 1899822.00, 86, 13.47, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(991, 'DUMMY-SKU-0991', 'Produk Sampel 991', 'Deskripsi untuk produk sampel nomor 991', 1, 3, 1512698.00, 71, 3.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(992, 'DUMMY-SKU-0992', 'Produk Sampel 992', 'Deskripsi untuk produk sampel nomor 992', 7, 4, 2262390.00, 88, 11.51, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(993, 'DUMMY-SKU-0993', 'Produk Sampel 993', 'Deskripsi untuk produk sampel nomor 993', 4, 6, 2130011.00, 86, 11.38, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(994, 'DUMMY-SKU-0994', 'Produk Sampel 994', 'Deskripsi untuk produk sampel nomor 994', 4, 7, 4695669.00, 109, 2.97, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(995, 'DUMMY-SKU-0995', 'Produk Sampel 995', 'Deskripsi untuk produk sampel nomor 995', 6, 3, 1209780.00, 41, 17.14, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(996, 'DUMMY-SKU-0996', 'Produk Sampel 996', 'Deskripsi untuk produk sampel nomor 996', 3, 1, 1068694.00, 105, 3.32, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(997, 'DUMMY-SKU-0997', 'Produk Sampel 997', 'Deskripsi untuk produk sampel nomor 997', 7, 2, 36909.00, 65, 15.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(998, 'DUMMY-SKU-0998', 'Produk Sampel 998', 'Deskripsi untuk produk sampel nomor 998', 1, 2, 2438597.00, 109, 10.85, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(999, 'DUMMY-SKU-0999', 'Produk Sampel 999', 'Deskripsi untuk produk sampel nomor 999', 5, 6, 652004.00, 22, 4.61, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1000, 'DUMMY-SKU-1000', 'Produk Sampel 1000', 'Deskripsi untuk produk sampel nomor 1000', 6, 1, 1817320.00, 52, 0.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1001, 'DUMMY-SKU-1001', 'Produk Sampel 1001', 'Deskripsi untuk produk sampel nomor 1001', 6, 1, 4800552.00, 62, 15.04, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1002, 'DUMMY-SKU-1002', 'Produk Sampel 1002', 'Deskripsi untuk produk sampel nomor 1002', 2, 5, 1896022.00, 26, 14.11, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1003, 'DUMMY-SKU-1003', 'Produk Sampel 1003', 'Deskripsi untuk produk sampel nomor 1003', 1, 7, 2787775.00, 13, 10.71, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1004, 'DUMMY-SKU-1004', 'Produk Sampel 1004', 'Deskripsi untuk produk sampel nomor 1004', 4, 1, 3924722.00, 78, 1.58, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1005, 'DUMMY-SKU-1005', 'Produk Sampel 1005', 'Deskripsi untuk produk sampel nomor 1005', 3, 3, 4226179.00, 24, 3.65, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1006, 'DUMMY-SKU-1006', 'Produk Sampel 1006', 'Deskripsi untuk produk sampel nomor 1006', 4, 6, 2596717.00, 34, 13.42, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1007, 'DUMMY-SKU-1007', 'Produk Sampel 1007', 'Deskripsi untuk produk sampel nomor 1007', 5, 7, 886113.00, 99, 18.99, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1008, 'DUMMY-SKU-1008', 'Produk Sampel 1008', 'Deskripsi untuk produk sampel nomor 1008', 1, 3, 3704968.00, 67, 13.47, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1009, 'DUMMY-SKU-1009', 'Produk Sampel 1009', 'Deskripsi untuk produk sampel nomor 1009', 5, 1, 2192395.00, 11, 15.78, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1010, 'DUMMY-SKU-1010', 'Produk Sampel 1010', 'Deskripsi untuk produk sampel nomor 1010', 7, 7, 1165692.00, 36, 12.57, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1011, 'DUMMY-SKU-1011', 'Produk Sampel 1011', 'Deskripsi untuk produk sampel nomor 1011', 3, 6, 4334199.00, 11, 9.66, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1012, 'DUMMY-SKU-1012', 'Produk Sampel 1012', 'Deskripsi untuk produk sampel nomor 1012', 3, 3, 2370284.00, 55, 16.93, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1013, 'DUMMY-SKU-1013', 'Produk Sampel 1013', 'Deskripsi untuk produk sampel nomor 1013', 6, 6, 649222.00, 52, 15.29, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1014, 'DUMMY-SKU-1014', 'Produk Sampel 1014', 'Deskripsi untuk produk sampel nomor 1014', 4, 2, 4313950.00, 56, 15.13, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1015, 'DUMMY-SKU-1015', 'Produk Sampel 1015', 'Deskripsi untuk produk sampel nomor 1015', 3, 4, 3005498.00, 49, 3.33, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1016, 'DUMMY-SKU-1016', 'Produk Sampel 1016', 'Deskripsi untuk produk sampel nomor 1016', 5, 5, 2509269.00, 56, 16.11, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1017, 'DUMMY-SKU-1017', 'Produk Sampel 1017', 'Deskripsi untuk produk sampel nomor 1017', 5, 6, 3525560.00, 47, 15.08, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1018, 'DUMMY-SKU-1018', 'Produk Sampel 1018', 'Deskripsi untuk produk sampel nomor 1018', 5, 7, 3138562.00, 51, 4.46, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1019, 'DUMMY-SKU-1019', 'Produk Sampel 1019', 'Deskripsi untuk produk sampel nomor 1019', 6, 4, 358067.00, 90, 16.48, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1020, 'DUMMY-SKU-1020', 'Produk Sampel 1020', 'Deskripsi untuk produk sampel nomor 1020', 5, 7, 3168353.00, 45, 18.10, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24'),
(1021, 'DUMMY-SKU-1021', 'Produk Sampel 1021', 'Deskripsi untuk produk sampel nomor 1021', 3, 3, 4000555.00, 85, 7.32, 'active', '2025-07-31 03:55:24', '2025-07-31 03:55:24');

--
-- Triggers `products`
--
DELIMITER $$
CREATE TRIGGER `after_product_update` AFTER UPDATE ON `products` FOR EACH ROW BEGIN
    DECLARE changes_detected BOOLEAN DEFAULT FALSE;
    
    -- Cek apakah ada perubahan signifikan
    IF OLD.name != NEW.name OR OLD.unit_price != NEW.unit_price OR 
       OLD.status != NEW.status OR OLD.minimum_stock != NEW.minimum_stock THEN
        SET changes_detected = TRUE;
    END IF;
    
    -- Log perubahan jika ada
    IF changes_detected THEN
        INSERT INTO audit_log (table_name, operation_type, record_id, old_values, new_values, changed_by)
        VALUES (
            'products',
            'UPDATE',
            NEW.id,
            JSON_OBJECT(
                'name', OLD.name,
                'unit_price', OLD.unit_price,
                'status', OLD.status,
                'minimum_stock', OLD.minimum_stock
            ),
            JSON_OBJECT(
                'name', NEW.name,
                'unit_price', NEW.unit_price,
                'status', NEW.status,
                'minimum_stock', NEW.minimum_stock
            ),
            USER()
        );
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `before_product_insert` BEFORE INSERT ON `products` FOR EACH ROW BEGIN
    -- Auto-generate SKU jika kosong
    IF NEW.sku IS NULL OR NEW.sku = '' THEN
        SET NEW.sku = CONCAT(
            (SELECT SUBSTRING(name, 1, 3) FROM categories WHERE id = NEW.category_id),
            LPAD(NEW.id, 3, '0'),
            DATE_FORMAT(NOW(), '%y')
        );
    END IF;
    
    -- Validasi harga minimum
    IF NEW.unit_price < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unit price cannot be negative';
    END IF;
    
    -- Set default minimum stock jika tidak diisi
    IF NEW.minimum_stock IS NULL OR NEW.minimum_stock < 1 THEN
        SET NEW.minimum_stock = 10;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `product_search_index`
--

CREATE TABLE `product_search_index` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `search_keywords` text DEFAULT NULL,
  `popularity_score` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product_search_index`
--

INSERT INTO `product_search_index` (`id`, `product_id`, `search_keywords`, `popularity_score`) VALUES
(1, 1, 'smartphone samsung galaxy android phone mobile', 95),
(2, 2, 'laptop asus vivobook computer notebook pc', 88),
(3, 3, 'earphone sony headphone audio sound music', 92),
(4, 4, 'kaos polo shirt clothing fashion pria men', 76),
(5, 5, 'jeans celana pants wanita women fashion', 82),
(6, 6, 'coffee kopi arabica premium beverage drink', 89),
(7, 7, 'tea teh green organic healthy beverage', 73),
(8, 8, 'printer canon office equipment electronic', 85),
(9, 9, 'paper kertas office supplies stationery', 68);

-- --------------------------------------------------------

--
-- Stand-in structure for view `product_stock_summary`
-- (See below for the actual view)
--
CREATE TABLE `product_stock_summary` (
`id` int(11)
,`sku` varchar(50)
,`product_name` varchar(200)
,`unit_price` decimal(10,2)
,`minimum_stock` int(11)
,`category_name` varchar(100)
,`supplier_name` varchar(150)
,`supplier_contact` varchar(100)
,`total_stock` decimal(32,0)
,`reserved_stock` decimal(32,0)
,`available_stock` decimal(33,0)
,`stock_status` varchar(12)
);

-- --------------------------------------------------------

--
-- Table structure for table `product_tags`
--

CREATE TABLE `product_tags` (
  `id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `color` varchar(7) DEFAULT '#007bff',
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product_tags`
--

INSERT INTO `product_tags` (`id`, `name`, `color`, `description`, `created_at`) VALUES
(1, 'New Arrival', '#28a745', 'Produk baru yang baru masuk', '2025-07-30 23:49:18'),
(2, 'Best Seller', '#ffc107', 'Produk terlaris', '2025-07-30 23:49:18'),
(3, 'On Sale', '#dc3545', 'Produk sedang diskon', '2025-07-30 23:49:18'),
(4, 'Limited Edition', '#6f42c1', 'Produk edisi terbatas', '2025-07-30 23:49:18'),
(5, 'Eco Friendly', '#20c997', 'Produk ramah lingkungan', '2025-07-30 23:49:18'),
(6, 'Premium', '#fd7e14', 'Produk premium', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Table structure for table `product_tag_relations`
--

CREATE TABLE `product_tag_relations` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `tag_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product_tag_relations`
--

INSERT INTO `product_tag_relations` (`id`, `product_id`, `tag_id`, `created_at`) VALUES
(1, 1, 1, '2025-07-30 23:49:18'),
(2, 1, 2, '2025-07-30 23:49:18'),
(3, 2, 1, '2025-07-30 23:49:18'),
(4, 2, 4, '2025-07-30 23:49:18'),
(5, 3, 2, '2025-07-30 23:49:18'),
(6, 3, 6, '2025-07-30 23:49:18'),
(7, 4, 3, '2025-07-30 23:49:18'),
(8, 4, 5, '2025-07-30 23:49:18'),
(9, 5, 2, '2025-07-30 23:49:18'),
(10, 5, 3, '2025-07-30 23:49:18'),
(11, 6, 5, '2025-07-30 23:49:18'),
(12, 6, 6, '2025-07-30 23:49:18'),
(13, 7, 5, '2025-07-30 23:49:18'),
(14, 8, 1, '2025-07-30 23:49:18'),
(15, 9, 2, '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Table structure for table `purchase_orders`
--

CREATE TABLE `purchase_orders` (
  `id` int(11) NOT NULL,
  `po_number` varchar(50) NOT NULL,
  `supplier_id` int(11) NOT NULL,
  `order_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `expected_delivery` date DEFAULT NULL,
  `total_amount` decimal(12,2) DEFAULT 0.00,
  `status` enum('pending','approved','received','cancelled') DEFAULT 'pending',
  `notes` text DEFAULT NULL,
  `created_by` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `purchase_orders`
--

INSERT INTO `purchase_orders` (`id`, `po_number`, `supplier_id`, `order_date`, `expected_delivery`, `total_amount`, `status`, `notes`, `created_by`) VALUES
(1, 'PO-2024-001', 1, '2025-07-30 23:49:18', '2024-02-15', 50000000.00, 'received', NULL, 'manager'),
(2, 'PO-2024-002', 2, '2025-07-30 23:49:18', '2024-02-20', 25000000.00, 'approved', NULL, 'manager'),
(3, 'PO-2024-003', 3, '2025-07-30 23:49:18', '2024-02-25', 15000000.00, 'pending', NULL, 'staff1'),
(4, 'PO-2024-004', 4, '2025-07-30 23:49:18', '2024-03-01', 8000000.00, 'received', NULL, 'manager'),
(5, 'PO-2024-005', 1, '2025-07-30 23:49:18', '2024-03-05', 30000000.00, 'approved', NULL, 'staff2'),
(6, 'PO-1753931389', 4, '2025-07-31 03:10:52', '2025-08-07', 650000.00, 'pending', NULL, 'manager');

-- --------------------------------------------------------

--
-- Table structure for table `purchase_order_details`
--

CREATE TABLE `purchase_order_details` (
  `id` int(11) NOT NULL,
  `po_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `quantity_ordered` int(11) NOT NULL,
  `quantity_received` int(11) DEFAULT 0,
  `unit_cost` decimal(10,2) NOT NULL,
  `line_total` decimal(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `purchase_order_details`
--

INSERT INTO `purchase_order_details` (`id`, `po_id`, `product_id`, `quantity_ordered`, `quantity_received`, `unit_cost`, `line_total`) VALUES
(1, 1, 1, 40, 40, 4200000.00, 168000000.00),
(2, 1, 2, 18, 18, 8000000.00, 144000000.00),
(3, 2, 4, 180, 0, 100000.00, 18000000.00),
(4, 2, 5, 100, 0, 200000.00, 20000000.00),
(5, 3, 6, 250, 0, 120000.00, 30000000.00),
(6, 3, 7, 200, 0, 70000.00, 14000000.00),
(7, 4, 8, 20, 20, 1750000.00, 35000000.00),
(8, 4, 9, 500, 500, 55000.00, 27500000.00),
(9, 5, 3, 50, 0, 2300000.00, 115000000.00),
(10, 6, 9, 10, 0, 65000.00, 650000.00);

-- --------------------------------------------------------

--
-- Stand-in structure for view `staff_order_view`
-- (See below for the actual view)
--
CREATE TABLE `staff_order_view` (
`id` int(11)
,`order_number` varchar(50)
,`customer_id` int(11)
,`order_date` timestamp
,`total_amount` decimal(12,2)
,`final_amount` decimal(12,2)
,`status` enum('pending','processing','shipped','delivered','cancelled')
,`created_by` varchar(100)
);

-- --------------------------------------------------------

--
-- Table structure for table `stock_inventory`
--

CREATE TABLE `stock_inventory` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `location_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 0,
  `reserved_quantity` int(11) NOT NULL DEFAULT 0,
  `batch_number` varchar(100) DEFAULT NULL,
  `expiry_date` date DEFAULT NULL,
  `cost_per_unit` decimal(10,2) DEFAULT 0.00,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `stock_inventory`
--

INSERT INTO `stock_inventory` (`id`, `product_id`, `location_id`, `quantity`, `reserved_quantity`, `batch_number`, `expiry_date`, `cost_per_unit`, `last_updated`) VALUES
(1, 1, 1, 15, 0, 'BATCH001', NULL, 4200000.00, '2025-07-31 05:11:01'),
(2, 1, 2, 15, 0, 'BATCH002', NULL, 4200000.00, '2025-07-30 23:49:18'),
(3, 2, 1, 10, 0, 'BATCH003', NULL, 8000000.00, '2025-07-30 23:49:18'),
(4, 2, 2, 8, 0, 'BATCH004', NULL, 8000000.00, '2025-07-30 23:49:18'),
(5, 3, 1, 30, 0, 'BATCH005', NULL, 2300000.00, '2025-07-30 23:49:18'),
(6, 3, 2, 20, 0, 'BATCH006', NULL, 2300000.00, '2025-07-30 23:49:18'),
(7, 4, 3, 100, 0, 'BATCH007', NULL, 100000.00, '2025-07-30 23:49:18'),
(8, 4, 4, 80, 0, 'BATCH008', NULL, 100000.00, '2025-07-30 23:49:18'),
(9, 5, 3, 60, 0, 'BATCH009', NULL, 200000.00, '2025-07-30 23:49:18'),
(10, 5, 4, 40, 0, 'BATCH010', NULL, 200000.00, '2025-07-30 23:49:18'),
(11, 6, 5, 150, 0, 'BATCH011', NULL, 120000.00, '2025-07-30 23:49:18'),
(12, 6, 6, 100, 0, 'BATCH012', NULL, 120000.00, '2025-07-30 23:49:18'),
(13, 7, 5, 120, 0, 'BATCH013', NULL, 70000.00, '2025-07-30 23:49:18'),
(14, 7, 6, 80, 0, 'BATCH014', NULL, 70000.00, '2025-07-30 23:49:18'),
(15, 8, 7, 12, 0, 'BATCH015', NULL, 1750000.00, '2025-07-30 23:49:18'),
(16, 9, 7, 300, 0, 'BATCH016', NULL, 55000.00, '2025-07-30 23:49:18'),
(17, 1, 2, 10, 0, 'BATCH001', NULL, 4200000.00, '2025-07-31 05:11:01'),
(30, 22, 4, 387, 0, 'BATCH-000022', '2028-01-14', 2553826.00, '2025-07-31 03:55:24'),
(31, 23, 5, 389, 0, 'BATCH-000023', '2027-02-01', 3672277.00, '2025-07-31 03:55:24'),
(32, 24, 7, 229, 0, 'BATCH-000024', '2028-07-24', 2143271.00, '2025-07-31 03:55:24'),
(33, 25, 5, 446, 0, 'BATCH-000025', '2026-03-03', 3599370.00, '2025-07-31 03:55:24'),
(34, 26, 7, 62, 0, 'BATCH-000026', '2027-05-18', 1390947.00, '2025-07-31 03:55:24'),
(35, 27, 1, 353, 0, 'BATCH-000027', '2028-01-14', 3458058.00, '2025-07-31 03:55:24'),
(36, 28, 5, 102, 0, 'BATCH-000028', '2027-05-20', 359339.00, '2025-07-31 03:55:24'),
(37, 29, 7, 323, 0, 'BATCH-000029', '2028-06-08', 3062468.00, '2025-07-31 03:55:24'),
(38, 30, 6, 539, 0, 'BATCH-000030', '2027-05-28', 2231981.00, '2025-07-31 03:55:24'),
(39, 31, 1, 339, 0, 'BATCH-000031', '2028-05-30', 2421586.00, '2025-07-31 03:55:24'),
(40, 32, 1, 543, 0, 'BATCH-000032', '2027-08-30', 4225722.00, '2025-07-31 03:55:24'),
(41, 33, 7, 509, 0, 'BATCH-000033', '2028-02-25', 186034.00, '2025-07-31 03:55:24'),
(42, 34, 7, 287, 0, 'BATCH-000034', '2027-10-03', 2938193.00, '2025-07-31 03:55:24'),
(43, 35, 3, 102, 0, 'BATCH-000035', '2026-11-14', 643370.00, '2025-07-31 03:55:24'),
(44, 36, 6, 417, 0, 'BATCH-000036', '2026-07-23', 3094325.00, '2025-07-31 03:55:24'),
(45, 37, 7, 260, 0, 'BATCH-000037', '2027-03-17', 3652614.00, '2025-07-31 03:55:24'),
(46, 38, 6, 353, 0, 'BATCH-000038', '2027-10-02', 1118220.00, '2025-07-31 03:55:24'),
(47, 39, 3, 161, 0, 'BATCH-000039', '2028-08-22', 99808.00, '2025-07-31 03:55:24'),
(48, 40, 3, 239, 0, 'BATCH-000040', '2026-02-26', 70503.00, '2025-07-31 03:55:24'),
(49, 41, 7, 477, 0, 'BATCH-000041', '2026-12-28', 510029.00, '2025-07-31 03:55:24'),
(50, 42, 4, 264, 0, 'BATCH-000042', '2027-05-27', 641271.00, '2025-07-31 03:55:24'),
(51, 43, 2, 457, 0, 'BATCH-000043', '2026-12-29', 1055592.00, '2025-07-31 03:55:24'),
(52, 44, 2, 90, 0, 'BATCH-000044', '2028-08-23', 2037264.00, '2025-07-31 03:55:24'),
(53, 45, 4, 467, 0, 'BATCH-000045', '2028-06-10', 3690668.00, '2025-07-31 03:55:24'),
(54, 46, 4, 64, 0, 'BATCH-000046', '2027-11-09', 792710.00, '2025-07-31 03:55:24'),
(55, 47, 7, 78, 0, 'BATCH-000047', '2027-07-20', 2367407.00, '2025-07-31 03:55:24'),
(56, 48, 1, 271, 0, 'BATCH-000048', '2026-08-24', 3223179.00, '2025-07-31 03:55:24'),
(57, 49, 7, 340, 0, 'BATCH-000049', '2026-04-05', 2702348.00, '2025-07-31 03:55:24'),
(58, 50, 6, 125, 0, 'BATCH-000050', '2027-02-21', 2239861.00, '2025-07-31 03:55:24'),
(59, 51, 3, 78, 0, 'BATCH-000051', '2027-01-20', 2794105.00, '2025-07-31 03:55:24'),
(60, 52, 1, 175, 0, 'BATCH-000052', '2026-08-03', 861499.00, '2025-07-31 03:55:24'),
(61, 53, 3, 224, 0, 'BATCH-000053', '2027-09-08', 4083587.00, '2025-07-31 03:55:24'),
(62, 54, 6, 87, 0, 'BATCH-000054', '2026-05-09', 1300803.00, '2025-07-31 03:55:24'),
(63, 55, 1, 438, 0, 'BATCH-000055', '2027-06-13', 817106.00, '2025-07-31 03:55:24'),
(64, 56, 3, 261, 0, 'BATCH-000056', '2028-08-17', 1814301.00, '2025-07-31 03:55:24'),
(65, 57, 2, 463, 0, 'BATCH-000057', '2027-06-30', 531756.00, '2025-07-31 03:55:24'),
(66, 58, 1, 430, 0, 'BATCH-000058', '2028-02-04', 1846118.00, '2025-07-31 03:55:24'),
(67, 59, 6, 506, 0, 'BATCH-000059', '2026-04-20', 3058244.00, '2025-07-31 03:55:24'),
(68, 60, 1, 379, 0, 'BATCH-000060', '2028-06-22', 1854116.00, '2025-07-31 03:55:24'),
(69, 61, 3, 484, 0, 'BATCH-000061', '2026-04-20', 3655912.00, '2025-07-31 03:55:24'),
(70, 62, 6, 342, 0, 'BATCH-000062', '2027-06-26', 3706598.00, '2025-07-31 03:55:24'),
(71, 63, 4, 225, 0, 'BATCH-000063', '2026-03-28', 1146105.00, '2025-07-31 03:55:24'),
(72, 64, 1, 377, 0, 'BATCH-000064', '2026-02-23', 791558.00, '2025-07-31 03:55:24'),
(73, 65, 6, 255, 0, 'BATCH-000065', '2027-12-22', 1082064.00, '2025-07-31 03:55:24'),
(74, 66, 1, 468, 0, 'BATCH-000066', '2028-05-31', 3443740.00, '2025-07-31 03:55:24'),
(75, 67, 2, 534, 0, 'BATCH-000067', '2026-04-27', 2467569.00, '2025-07-31 03:55:24'),
(76, 68, 4, 380, 0, 'BATCH-000068', '2028-08-06', 2845127.00, '2025-07-31 03:55:24'),
(77, 69, 3, 67, 0, 'BATCH-000069', '2026-02-12', 4417514.00, '2025-07-31 03:55:24'),
(78, 70, 6, 204, 0, 'BATCH-000070', '2028-10-14', 164075.00, '2025-07-31 03:55:24'),
(79, 71, 2, 493, 0, 'BATCH-000071', '2028-05-12', 2371247.00, '2025-07-31 03:55:24'),
(80, 72, 1, 51, 0, 'BATCH-000072', '2027-11-24', 1459798.00, '2025-07-31 03:55:24'),
(81, 73, 5, 103, 0, 'BATCH-000073', '2027-12-16', 551581.00, '2025-07-31 03:55:24'),
(82, 74, 4, 218, 0, 'BATCH-000074', '2026-03-29', 1360787.00, '2025-07-31 03:55:24'),
(83, 75, 3, 392, 0, 'BATCH-000075', '2027-05-19', 1483730.00, '2025-07-31 03:55:24'),
(84, 76, 2, 78, 0, 'BATCH-000076', '2027-11-18', 607764.00, '2025-07-31 03:55:24'),
(85, 77, 5, 59, 0, 'BATCH-000077', '2026-03-09', 693013.00, '2025-07-31 03:55:24'),
(86, 78, 5, 412, 0, 'BATCH-000078', '2028-01-15', 1886470.00, '2025-07-31 03:55:24'),
(87, 79, 7, 250, 0, 'BATCH-000079', '2026-08-25', 3837284.00, '2025-07-31 03:55:24'),
(88, 80, 5, 332, 0, 'BATCH-000080', '2028-09-04', 296305.00, '2025-07-31 03:55:24'),
(89, 81, 4, 119, 0, 'BATCH-000081', '2026-11-15', 224685.00, '2025-07-31 03:55:24'),
(90, 82, 3, 385, 0, 'BATCH-000082', '2026-10-22', 1478158.00, '2025-07-31 03:55:24'),
(91, 83, 6, 131, 0, 'BATCH-000083', '2026-12-22', 720944.00, '2025-07-31 03:55:24'),
(92, 84, 6, 321, 0, 'BATCH-000084', '2026-11-24', 3965101.00, '2025-07-31 03:55:24'),
(93, 85, 4, 463, 0, 'BATCH-000085', '2027-11-11', 3545277.00, '2025-07-31 03:55:24'),
(94, 86, 7, 299, 0, 'BATCH-000086', '2027-08-27', 1768716.00, '2025-07-31 03:55:24'),
(95, 87, 2, 525, 0, 'BATCH-000087', '2026-04-14', 2414382.00, '2025-07-31 03:55:24'),
(96, 88, 4, 353, 0, 'BATCH-000088', '2028-01-06', 3278974.00, '2025-07-31 03:55:24'),
(97, 89, 4, 222, 0, 'BATCH-000089', '2026-08-22', 35169.00, '2025-07-31 03:55:24'),
(98, 90, 3, 56, 0, 'BATCH-000090', '2028-05-22', 878049.00, '2025-07-31 03:55:24'),
(99, 91, 3, 328, 0, 'BATCH-000091', '2027-06-10', 3734250.00, '2025-07-31 03:55:24'),
(100, 92, 5, 413, 0, 'BATCH-000092', '2028-01-05', 1637923.00, '2025-07-31 03:55:24'),
(101, 93, 5, 219, 0, 'BATCH-000093', '2027-10-24', 745469.00, '2025-07-31 03:55:24'),
(102, 94, 7, 85, 0, 'BATCH-000094', '2027-10-06', 3935998.00, '2025-07-31 03:55:24'),
(103, 95, 4, 523, 0, 'BATCH-000095', '2026-08-08', 576475.00, '2025-07-31 03:55:24'),
(104, 96, 1, 491, 0, 'BATCH-000096', '2026-10-08', 2826941.00, '2025-07-31 03:55:24'),
(105, 97, 3, 530, 0, 'BATCH-000097', '2027-12-31', 2858367.00, '2025-07-31 03:55:24'),
(106, 98, 1, 240, 0, 'BATCH-000098', '2028-01-29', 2349627.00, '2025-07-31 03:55:24'),
(107, 99, 3, 283, 0, 'BATCH-000099', '2026-05-22', 806292.00, '2025-07-31 03:55:24'),
(108, 100, 4, 136, 0, 'BATCH-000100', '2026-09-27', 3150559.00, '2025-07-31 03:55:24'),
(109, 101, 6, 403, 0, 'BATCH-000101', '2026-10-11', 744005.00, '2025-07-31 03:55:24'),
(110, 102, 1, 418, 0, 'BATCH-000102', '2027-07-30', 2410402.00, '2025-07-31 03:55:24'),
(111, 103, 1, 304, 0, 'BATCH-000103', '2027-05-21', 3915709.00, '2025-07-31 03:55:24'),
(112, 104, 7, 508, 0, 'BATCH-000104', '2028-06-17', 2757680.00, '2025-07-31 03:55:24'),
(113, 105, 4, 227, 0, 'BATCH-000105', '2027-05-04', 1123897.00, '2025-07-31 03:55:24'),
(114, 106, 6, 307, 0, 'BATCH-000106', '2026-02-17', 2536609.00, '2025-07-31 03:55:24'),
(115, 107, 6, 68, 0, 'BATCH-000107', '2028-09-05', 2933139.00, '2025-07-31 03:55:24'),
(116, 108, 3, 57, 0, 'BATCH-000108', '2028-07-13', 2013255.00, '2025-07-31 03:55:24'),
(117, 109, 4, 213, 0, 'BATCH-000109', '2026-03-02', 874404.00, '2025-07-31 03:55:24'),
(118, 110, 7, 409, 0, 'BATCH-000110', '2026-02-16', 4258756.00, '2025-07-31 03:55:24'),
(119, 111, 5, 284, 0, 'BATCH-000111', '2027-01-24', 1838662.00, '2025-07-31 03:55:24'),
(120, 112, 7, 304, 0, 'BATCH-000112', '2028-01-07', 114012.00, '2025-07-31 03:55:24'),
(121, 113, 7, 480, 0, 'BATCH-000113', '2027-01-03', 586341.00, '2025-07-31 03:55:24'),
(122, 114, 5, 400, 0, 'BATCH-000114', '2027-11-13', 792099.00, '2025-07-31 03:55:24'),
(123, 115, 7, 547, 0, 'BATCH-000115', '2026-10-22', 1608196.00, '2025-07-31 03:55:24'),
(124, 116, 7, 446, 0, 'BATCH-000116', '2026-03-14', 3863259.00, '2025-07-31 03:55:24'),
(125, 117, 2, 122, 0, 'BATCH-000117', '2026-11-20', 246049.00, '2025-07-31 03:55:24'),
(126, 118, 3, 398, 0, 'BATCH-000118', '2027-01-29', 3382816.00, '2025-07-31 03:55:24'),
(127, 119, 5, 542, 0, 'BATCH-000119', '2028-10-03', 4288021.00, '2025-07-31 03:55:24'),
(128, 120, 6, 156, 0, 'BATCH-000120', '2027-10-13', 2195185.00, '2025-07-31 03:55:24'),
(129, 121, 4, 209, 0, 'BATCH-000121', '2028-08-09', 3030935.00, '2025-07-31 03:55:24'),
(130, 122, 5, 499, 0, 'BATCH-000122', '2028-02-14', 212875.00, '2025-07-31 03:55:24'),
(131, 123, 7, 434, 0, 'BATCH-000123', '2028-07-17', 922428.00, '2025-07-31 03:55:24'),
(132, 124, 3, 519, 0, 'BATCH-000124', '2028-03-02', 61889.00, '2025-07-31 03:55:24'),
(133, 125, 6, 438, 0, 'BATCH-000125', '2027-09-14', 2923357.00, '2025-07-31 03:55:24'),
(134, 126, 4, 209, 0, 'BATCH-000126', '2026-09-24', 1110306.00, '2025-07-31 03:55:24'),
(135, 127, 4, 438, 0, 'BATCH-000127', '2027-02-05', 2454964.00, '2025-07-31 03:55:24'),
(136, 128, 5, 222, 0, 'BATCH-000128', '2028-08-25', 3029848.00, '2025-07-31 03:55:24'),
(137, 129, 4, 374, 0, 'BATCH-000129', '2027-11-04', 1297861.00, '2025-07-31 03:55:24'),
(138, 130, 4, 352, 0, 'BATCH-000130', '2027-07-28', 4160499.00, '2025-07-31 03:55:24'),
(139, 131, 7, 92, 0, 'BATCH-000131', '2027-06-20', 1336658.00, '2025-07-31 03:55:24'),
(140, 132, 7, 475, 0, 'BATCH-000132', '2027-03-19', 2385434.00, '2025-07-31 03:55:24'),
(141, 133, 3, 235, 0, 'BATCH-000133', '2027-12-10', 1346412.00, '2025-07-31 03:55:24'),
(142, 134, 4, 205, 0, 'BATCH-000134', '2026-09-14', 1011221.00, '2025-07-31 03:55:24'),
(143, 135, 3, 270, 0, 'BATCH-000135', '2028-08-23', 1701613.00, '2025-07-31 03:55:24'),
(144, 136, 1, 140, 0, 'BATCH-000136', '2028-01-11', 156336.00, '2025-07-31 03:55:24'),
(145, 137, 1, 53, 0, 'BATCH-000137', '2028-09-21', 3704483.00, '2025-07-31 03:55:24'),
(146, 138, 2, 325, 0, 'BATCH-000138', '2026-06-23', 386457.00, '2025-07-31 03:55:24'),
(147, 139, 7, 367, 0, 'BATCH-000139', '2026-09-27', 1403552.00, '2025-07-31 03:55:24'),
(148, 140, 6, 138, 0, 'BATCH-000140', '2027-03-20', 2527245.00, '2025-07-31 03:55:24'),
(149, 141, 4, 74, 0, 'BATCH-000141', '2027-09-29', 4069532.00, '2025-07-31 03:55:24'),
(150, 142, 5, 401, 0, 'BATCH-000142', '2027-05-10', 1054571.00, '2025-07-31 03:55:24'),
(151, 143, 6, 96, 0, 'BATCH-000143', '2026-08-03', 2997730.00, '2025-07-31 03:55:24'),
(152, 144, 6, 445, 0, 'BATCH-000144', '2027-12-11', 213024.00, '2025-07-31 03:55:24'),
(153, 145, 2, 424, 0, 'BATCH-000145', '2026-08-26', 3663239.00, '2025-07-31 03:55:24'),
(154, 146, 3, 398, 0, 'BATCH-000146', '2026-08-16', 4148010.00, '2025-07-31 03:55:24'),
(155, 147, 7, 156, 0, 'BATCH-000147', '2026-04-18', 3457106.00, '2025-07-31 03:55:24'),
(156, 148, 5, 373, 0, 'BATCH-000148', '2027-05-05', 1710526.00, '2025-07-31 03:55:24'),
(157, 149, 4, 236, 0, 'BATCH-000149', '2027-01-23', 3096771.00, '2025-07-31 03:55:24'),
(158, 150, 3, 391, 0, 'BATCH-000150', '2027-01-28', 3551775.00, '2025-07-31 03:55:24'),
(159, 151, 6, 460, 0, 'BATCH-000151', '2027-09-15', 2332418.00, '2025-07-31 03:55:24'),
(160, 152, 6, 261, 0, 'BATCH-000152', '2028-01-27', 1737527.00, '2025-07-31 03:55:24'),
(161, 153, 6, 298, 0, 'BATCH-000153', '2026-11-19', 4458082.00, '2025-07-31 03:55:24'),
(162, 154, 1, 206, 0, 'BATCH-000154', '2027-03-04', 294352.00, '2025-07-31 03:55:24'),
(163, 155, 1, 242, 0, 'BATCH-000155', '2027-08-25', 3270321.00, '2025-07-31 03:55:24'),
(164, 156, 7, 208, 0, 'BATCH-000156', '2028-07-06', 2289730.00, '2025-07-31 03:55:24'),
(165, 157, 7, 438, 0, 'BATCH-000157', '2026-11-28', 893425.00, '2025-07-31 03:55:24'),
(166, 158, 1, 423, 0, 'BATCH-000158', '2027-07-12', 1888771.00, '2025-07-31 03:55:24'),
(167, 159, 4, 160, 0, 'BATCH-000159', '2027-10-04', 1892915.00, '2025-07-31 03:55:24'),
(168, 160, 2, 539, 0, 'BATCH-000160', '2026-06-26', 3691563.00, '2025-07-31 03:55:24'),
(169, 161, 5, 423, 0, 'BATCH-000161', '2028-04-22', 3791910.00, '2025-07-31 03:55:24'),
(170, 162, 6, 173, 0, 'BATCH-000162', '2028-09-23', 520489.00, '2025-07-31 03:55:24'),
(171, 163, 5, 523, 0, 'BATCH-000163', '2028-02-24', 4294913.00, '2025-07-31 03:55:24'),
(172, 164, 4, 342, 0, 'BATCH-000164', '2027-04-29', 2407607.00, '2025-07-31 03:55:24'),
(173, 165, 3, 485, 0, 'BATCH-000165', '2027-05-12', 3333232.00, '2025-07-31 03:55:24'),
(174, 166, 2, 153, 0, 'BATCH-000166', '2026-07-22', 1194466.00, '2025-07-31 03:55:24'),
(175, 167, 6, 127, 0, 'BATCH-000167', '2027-03-12', 2621980.00, '2025-07-31 03:55:24'),
(176, 168, 5, 368, 0, 'BATCH-000168', '2026-07-05', 3999555.00, '2025-07-31 03:55:24'),
(177, 169, 7, 107, 0, 'BATCH-000169', '2028-01-04', 879106.00, '2025-07-31 03:55:24'),
(178, 170, 6, 373, 0, 'BATCH-000170', '2027-12-26', 2481283.00, '2025-07-31 03:55:24'),
(179, 171, 5, 360, 0, 'BATCH-000171', '2026-06-16', 3784601.00, '2025-07-31 03:55:24'),
(180, 172, 6, 231, 0, 'BATCH-000172', '2027-05-28', 1546215.00, '2025-07-31 03:55:24'),
(181, 173, 2, 164, 0, 'BATCH-000173', '2027-02-21', 1211045.00, '2025-07-31 03:55:24'),
(182, 174, 2, 60, 0, 'BATCH-000174', '2027-10-04', 57050.00, '2025-07-31 03:55:24'),
(183, 175, 2, 54, 0, 'BATCH-000175', '2027-03-25', 385711.00, '2025-07-31 03:55:24'),
(184, 176, 2, 304, 0, 'BATCH-000176', '2026-04-23', 4089951.00, '2025-07-31 03:55:24'),
(185, 177, 2, 378, 0, 'BATCH-000177', '2027-05-04', 1522525.00, '2025-07-31 03:55:24'),
(186, 178, 3, 286, 0, 'BATCH-000178', '2027-05-19', 4352072.00, '2025-07-31 03:55:24'),
(187, 179, 3, 90, 0, 'BATCH-000179', '2026-09-03', 3848291.00, '2025-07-31 03:55:24'),
(188, 180, 5, 292, 0, 'BATCH-000180', '2027-09-14', 2358054.00, '2025-07-31 03:55:24'),
(189, 181, 6, 331, 0, 'BATCH-000181', '2026-12-31', 13128.00, '2025-07-31 03:55:24'),
(190, 182, 7, 526, 0, 'BATCH-000182', '2028-03-26', 412545.00, '2025-07-31 03:55:24'),
(191, 183, 1, 117, 0, 'BATCH-000183', '2027-04-01', 3351551.00, '2025-07-31 03:55:24'),
(192, 184, 3, 504, 0, 'BATCH-000184', '2026-10-13', 2577852.00, '2025-07-31 03:55:24'),
(193, 185, 1, 387, 0, 'BATCH-000185', '2026-06-20', 3139532.00, '2025-07-31 03:55:24'),
(194, 186, 1, 121, 0, 'BATCH-000186', '2027-08-22', 1965384.00, '2025-07-31 03:55:24'),
(195, 187, 4, 543, 0, 'BATCH-000187', '2027-08-07', 3736592.00, '2025-07-31 03:55:24'),
(196, 188, 4, 482, 0, 'BATCH-000188', '2028-07-27', 4367027.00, '2025-07-31 03:55:24'),
(197, 189, 1, 362, 0, 'BATCH-000189', '2028-04-08', 638508.00, '2025-07-31 03:55:24'),
(198, 190, 3, 72, 0, 'BATCH-000190', '2027-01-08', 2691063.00, '2025-07-31 03:55:24'),
(199, 191, 7, 511, 0, 'BATCH-000191', '2028-03-22', 727397.00, '2025-07-31 03:55:24'),
(200, 192, 4, 417, 0, 'BATCH-000192', '2027-01-11', 2433111.00, '2025-07-31 03:55:24'),
(201, 193, 5, 359, 0, 'BATCH-000193', '2026-06-26', 4049968.00, '2025-07-31 03:55:24'),
(202, 194, 1, 300, 0, 'BATCH-000194', '2027-02-18', 1969075.00, '2025-07-31 03:55:24'),
(203, 195, 1, 435, 0, 'BATCH-000195', '2028-04-12', 3257378.00, '2025-07-31 03:55:24'),
(204, 196, 2, 441, 0, 'BATCH-000196', '2027-01-06', 1697605.00, '2025-07-31 03:55:24'),
(205, 197, 6, 94, 0, 'BATCH-000197', '2028-07-27', 1342970.00, '2025-07-31 03:55:24'),
(206, 198, 6, 471, 0, 'BATCH-000198', '2028-09-26', 1544602.00, '2025-07-31 03:55:24'),
(207, 199, 6, 501, 0, 'BATCH-000199', '2026-07-06', 429832.00, '2025-07-31 03:55:24'),
(208, 200, 7, 374, 0, 'BATCH-000200', '2026-11-11', 2231541.00, '2025-07-31 03:55:24'),
(209, 201, 5, 322, 0, 'BATCH-000201', '2028-07-19', 4014277.00, '2025-07-31 03:55:24'),
(210, 202, 6, 59, 0, 'BATCH-000202', '2028-06-24', 1554200.00, '2025-07-31 03:55:24'),
(211, 203, 1, 229, 0, 'BATCH-000203', '2027-08-14', 3346083.00, '2025-07-31 03:55:24'),
(212, 204, 1, 478, 0, 'BATCH-000204', '2026-09-19', 2728502.00, '2025-07-31 03:55:24'),
(213, 205, 3, 437, 0, 'BATCH-000205', '2028-08-04', 1255346.00, '2025-07-31 03:55:24'),
(214, 206, 5, 197, 0, 'BATCH-000206', '2027-09-17', 487233.00, '2025-07-31 03:55:24'),
(215, 207, 6, 235, 0, 'BATCH-000207', '2027-10-26', 350025.00, '2025-07-31 03:55:24'),
(216, 208, 4, 105, 0, 'BATCH-000208', '2026-07-01', 2004752.00, '2025-07-31 03:55:24'),
(217, 209, 6, 261, 0, 'BATCH-000209', '2028-06-06', 189824.00, '2025-07-31 03:55:24'),
(218, 210, 5, 531, 0, 'BATCH-000210', '2028-09-13', 4136904.00, '2025-07-31 03:55:24'),
(219, 211, 5, 436, 0, 'BATCH-000211', '2028-02-18', 1994464.00, '2025-07-31 03:55:24'),
(220, 212, 7, 262, 0, 'BATCH-000212', '2026-10-27', 423963.00, '2025-07-31 03:55:24'),
(221, 213, 5, 517, 0, 'BATCH-000213', '2028-02-17', 4279762.00, '2025-07-31 03:55:24'),
(222, 214, 4, 356, 0, 'BATCH-000214', '2027-09-10', 529295.00, '2025-07-31 03:55:24'),
(223, 215, 6, 389, 0, 'BATCH-000215', '2028-09-28', 3799633.00, '2025-07-31 03:55:24'),
(224, 216, 3, 502, 0, 'BATCH-000216', '2027-11-26', 2813082.00, '2025-07-31 03:55:24'),
(225, 217, 1, 396, 0, 'BATCH-000217', '2026-06-03', 2528772.00, '2025-07-31 03:55:24'),
(226, 218, 3, 252, 0, 'BATCH-000218', '2028-03-09', 2921184.00, '2025-07-31 03:55:24'),
(227, 219, 7, 378, 0, 'BATCH-000219', '2027-07-10', 3047709.00, '2025-07-31 03:55:24'),
(228, 220, 6, 506, 0, 'BATCH-000220', '2026-08-13', 1160175.00, '2025-07-31 03:55:24'),
(229, 221, 5, 376, 0, 'BATCH-000221', '2026-08-28', 487767.00, '2025-07-31 03:55:24'),
(230, 222, 7, 123, 0, 'BATCH-000222', '2026-03-22', 3742043.00, '2025-07-31 03:55:24'),
(231, 223, 7, 272, 0, 'BATCH-000223', '2026-10-17', 4423752.00, '2025-07-31 03:55:24'),
(232, 224, 1, 370, 0, 'BATCH-000224', '2028-06-03', 1653428.00, '2025-07-31 03:55:24'),
(233, 225, 2, 134, 0, 'BATCH-000225', '2026-04-25', 4213932.00, '2025-07-31 03:55:24'),
(234, 226, 3, 165, 0, 'BATCH-000226', '2028-08-15', 4363104.00, '2025-07-31 03:55:24'),
(235, 227, 1, 206, 0, 'BATCH-000227', '2027-04-09', 1128086.00, '2025-07-31 03:55:24'),
(236, 228, 7, 503, 0, 'BATCH-000228', '2028-02-06', 4434194.00, '2025-07-31 03:55:24'),
(237, 229, 5, 314, 0, 'BATCH-000229', '2027-08-10', 965608.00, '2025-07-31 03:55:24'),
(238, 230, 3, 187, 0, 'BATCH-000230', '2026-09-13', 1445922.00, '2025-07-31 03:55:24'),
(239, 231, 7, 345, 0, 'BATCH-000231', '2026-09-11', 1648899.00, '2025-07-31 03:55:24'),
(240, 232, 1, 351, 0, 'BATCH-000232', '2027-09-19', 864859.00, '2025-07-31 03:55:24'),
(241, 233, 2, 141, 0, 'BATCH-000233', '2027-05-07', 3497870.00, '2025-07-31 03:55:24'),
(242, 234, 4, 91, 0, 'BATCH-000234', '2028-09-18', 2627989.00, '2025-07-31 03:55:24'),
(243, 235, 1, 211, 0, 'BATCH-000235', '2027-08-20', 3984780.00, '2025-07-31 03:55:24'),
(244, 236, 5, 495, 0, 'BATCH-000236', '2026-12-18', 4324350.00, '2025-07-31 03:55:24'),
(245, 237, 6, 156, 0, 'BATCH-000237', '2027-09-30', 1897096.00, '2025-07-31 03:55:24'),
(246, 238, 2, 78, 0, 'BATCH-000238', '2027-06-04', 1343675.00, '2025-07-31 03:55:24'),
(247, 239, 1, 115, 0, 'BATCH-000239', '2027-10-28', 3627707.00, '2025-07-31 03:55:24'),
(248, 240, 1, 105, 0, 'BATCH-000240', '2026-09-22', 3877992.00, '2025-07-31 03:55:24'),
(249, 241, 5, 222, 0, 'BATCH-000241', '2028-09-25', 3718896.00, '2025-07-31 03:55:24'),
(250, 242, 2, 329, 0, 'BATCH-000242', '2026-07-19', 875896.00, '2025-07-31 03:55:24'),
(251, 243, 4, 368, 0, 'BATCH-000243', '2028-05-29', 1613742.00, '2025-07-31 03:55:24'),
(252, 244, 2, 75, 0, 'BATCH-000244', '2027-09-04', 3478136.00, '2025-07-31 03:55:24'),
(253, 245, 1, 143, 0, 'BATCH-000245', '2027-10-20', 2699441.00, '2025-07-31 03:55:24'),
(254, 246, 1, 393, 0, 'BATCH-000246', '2026-06-25', 3091459.00, '2025-07-31 03:55:24'),
(255, 247, 7, 464, 0, 'BATCH-000247', '2026-08-28', 2627731.00, '2025-07-31 03:55:24'),
(256, 248, 2, 350, 0, 'BATCH-000248', '2026-08-11', 815477.00, '2025-07-31 03:55:24'),
(257, 249, 3, 50, 0, 'BATCH-000249', '2026-04-15', 1774438.00, '2025-07-31 03:55:24'),
(258, 250, 6, 277, 0, 'BATCH-000250', '2026-05-01', 490551.00, '2025-07-31 03:55:24'),
(259, 251, 2, 522, 0, 'BATCH-000251', '2028-09-16', 4441584.00, '2025-07-31 03:55:24'),
(260, 252, 1, 158, 0, 'BATCH-000252', '2028-10-03', 1140766.00, '2025-07-31 03:55:24'),
(261, 253, 3, 465, 0, 'BATCH-000253', '2026-08-21', 2426372.00, '2025-07-31 03:55:24'),
(262, 254, 1, 412, 0, 'BATCH-000254', '2027-03-26', 4255726.00, '2025-07-31 03:55:24'),
(263, 255, 4, 253, 0, 'BATCH-000255', '2027-12-20', 1089984.00, '2025-07-31 03:55:24'),
(264, 256, 1, 502, 0, 'BATCH-000256', '2026-06-20', 62851.00, '2025-07-31 03:55:24'),
(265, 257, 5, 97, 0, 'BATCH-000257', '2027-09-17', 3181192.00, '2025-07-31 03:55:24'),
(266, 258, 6, 319, 0, 'BATCH-000258', '2027-06-10', 3970077.00, '2025-07-31 03:55:24'),
(267, 259, 7, 492, 0, 'BATCH-000259', '2028-01-03', 3971795.00, '2025-07-31 03:55:24'),
(268, 260, 2, 437, 0, 'BATCH-000260', '2026-02-23', 3661482.00, '2025-07-31 03:55:24'),
(269, 261, 7, 271, 0, 'BATCH-000261', '2026-11-15', 584938.00, '2025-07-31 03:55:24'),
(270, 262, 6, 270, 0, 'BATCH-000262', '2028-07-21', 965623.00, '2025-07-31 03:55:24'),
(271, 263, 3, 90, 0, 'BATCH-000263', '2027-01-31', 2740693.00, '2025-07-31 03:55:24'),
(272, 264, 7, 458, 0, 'BATCH-000264', '2026-11-24', 254443.00, '2025-07-31 03:55:24'),
(273, 265, 3, 394, 0, 'BATCH-000265', '2026-12-25', 2689754.00, '2025-07-31 03:55:24'),
(274, 266, 7, 111, 0, 'BATCH-000266', '2027-11-26', 4387826.00, '2025-07-31 03:55:24'),
(275, 267, 7, 242, 0, 'BATCH-000267', '2027-01-07', 2566360.00, '2025-07-31 03:55:24'),
(276, 268, 6, 215, 0, 'BATCH-000268', '2026-09-15', 759451.00, '2025-07-31 03:55:24'),
(277, 269, 1, 148, 0, 'BATCH-000269', '2027-08-13', 1028505.00, '2025-07-31 03:55:24'),
(278, 270, 4, 321, 0, 'BATCH-000270', '2027-02-08', 1173629.00, '2025-07-31 03:55:24'),
(279, 271, 2, 71, 0, 'BATCH-000271', '2028-01-18', 2157786.00, '2025-07-31 03:55:24'),
(280, 272, 2, 396, 0, 'BATCH-000272', '2028-03-29', 3968764.00, '2025-07-31 03:55:24'),
(281, 273, 1, 290, 0, 'BATCH-000273', '2026-12-21', 917382.00, '2025-07-31 03:55:24'),
(282, 274, 1, 308, 0, 'BATCH-000274', '2027-06-26', 104096.00, '2025-07-31 03:55:24'),
(283, 275, 4, 422, 0, 'BATCH-000275', '2026-03-05', 4308933.00, '2025-07-31 03:55:24'),
(284, 276, 5, 278, 0, 'BATCH-000276', '2026-11-17', 444258.00, '2025-07-31 03:55:24'),
(285, 277, 5, 410, 0, 'BATCH-000277', '2028-04-06', 3769028.00, '2025-07-31 03:55:24'),
(286, 278, 6, 243, 0, 'BATCH-000278', '2027-09-15', 3703733.00, '2025-07-31 03:55:24'),
(287, 279, 3, 112, 0, 'BATCH-000279', '2027-12-03', 4501041.00, '2025-07-31 03:55:24'),
(288, 280, 7, 469, 0, 'BATCH-000280', '2026-11-15', 4266727.00, '2025-07-31 03:55:24'),
(289, 281, 6, 267, 0, 'BATCH-000281', '2027-09-26', 3315225.00, '2025-07-31 03:55:24'),
(290, 282, 6, 77, 0, 'BATCH-000282', '2028-01-15', 1929300.00, '2025-07-31 03:55:24'),
(291, 283, 7, 359, 0, 'BATCH-000283', '2026-06-30', 4128820.00, '2025-07-31 03:55:24'),
(292, 284, 1, 464, 0, 'BATCH-000284', '2028-04-06', 2324023.00, '2025-07-31 03:55:24'),
(293, 285, 2, 207, 0, 'BATCH-000285', '2026-03-28', 1617540.00, '2025-07-31 03:55:24'),
(294, 286, 5, 529, 0, 'BATCH-000286', '2028-09-27', 4482402.00, '2025-07-31 03:55:24'),
(295, 287, 1, 182, 0, 'BATCH-000287', '2026-07-20', 355142.00, '2025-07-31 03:55:24'),
(296, 288, 7, 92, 0, 'BATCH-000288', '2028-05-11', 4151341.00, '2025-07-31 03:55:24'),
(297, 289, 1, 414, 0, 'BATCH-000289', '2027-01-12', 2555592.00, '2025-07-31 03:55:24'),
(298, 290, 6, 147, 0, 'BATCH-000290', '2027-10-26', 2721454.00, '2025-07-31 03:55:24'),
(299, 291, 1, 402, 0, 'BATCH-000291', '2026-08-31', 4367723.00, '2025-07-31 03:55:24'),
(300, 292, 2, 81, 0, 'BATCH-000292', '2028-01-27', 2103431.00, '2025-07-31 03:55:24'),
(301, 293, 1, 193, 0, 'BATCH-000293', '2026-02-16', 1103184.00, '2025-07-31 03:55:24'),
(302, 294, 2, 74, 0, 'BATCH-000294', '2028-03-18', 3426241.00, '2025-07-31 03:55:24'),
(303, 295, 4, 541, 0, 'BATCH-000295', '2027-08-06', 3754832.00, '2025-07-31 03:55:24'),
(304, 296, 4, 538, 0, 'BATCH-000296', '2027-03-01', 293983.00, '2025-07-31 03:55:24'),
(305, 297, 1, 258, 0, 'BATCH-000297', '2028-01-18', 1606945.00, '2025-07-31 03:55:24'),
(306, 298, 5, 548, 0, 'BATCH-000298', '2026-06-19', 3281533.00, '2025-07-31 03:55:24'),
(307, 299, 2, 478, 0, 'BATCH-000299', '2027-11-19', 3315472.00, '2025-07-31 03:55:24'),
(308, 300, 5, 176, 0, 'BATCH-000300', '2026-08-02', 814581.00, '2025-07-31 03:55:24'),
(309, 301, 3, 117, 0, 'BATCH-000301', '2027-11-27', 4259952.00, '2025-07-31 03:55:24'),
(310, 302, 6, 420, 0, 'BATCH-000302', '2027-08-09', 2594495.00, '2025-07-31 03:55:24'),
(311, 303, 2, 175, 0, 'BATCH-000303', '2027-12-01', 2767711.00, '2025-07-31 03:55:24'),
(312, 304, 1, 242, 0, 'BATCH-000304', '2028-03-26', 3582799.00, '2025-07-31 03:55:24'),
(313, 305, 5, 364, 0, 'BATCH-000305', '2026-12-31', 3627511.00, '2025-07-31 03:55:24'),
(314, 306, 1, 359, 0, 'BATCH-000306', '2026-04-17', 2441659.00, '2025-07-31 03:55:24'),
(315, 307, 4, 397, 0, 'BATCH-000307', '2026-04-23', 1572628.00, '2025-07-31 03:55:24'),
(316, 308, 4, 223, 0, 'BATCH-000308', '2026-11-21', 2049224.00, '2025-07-31 03:55:24'),
(317, 309, 3, 300, 0, 'BATCH-000309', '2027-02-15', 1913122.00, '2025-07-31 03:55:24'),
(318, 310, 7, 320, 0, 'BATCH-000310', '2028-04-24', 2125831.00, '2025-07-31 03:55:24'),
(319, 311, 7, 86, 0, 'BATCH-000311', '2027-11-27', 609098.00, '2025-07-31 03:55:24'),
(320, 312, 5, 494, 0, 'BATCH-000312', '2027-05-14', 3140286.00, '2025-07-31 03:55:24'),
(321, 313, 1, 160, 0, 'BATCH-000313', '2028-08-02', 4193285.00, '2025-07-31 03:55:24'),
(322, 314, 7, 392, 0, 'BATCH-000314', '2028-02-02', 2845631.00, '2025-07-31 03:55:24'),
(323, 315, 7, 461, 0, 'BATCH-000315', '2026-11-07', 4307293.00, '2025-07-31 03:55:24'),
(324, 316, 7, 424, 0, 'BATCH-000316', '2028-09-27', 2817474.00, '2025-07-31 03:55:24'),
(325, 317, 2, 112, 0, 'BATCH-000317', '2026-02-22', 3414837.00, '2025-07-31 03:55:24'),
(326, 318, 5, 179, 0, 'BATCH-000318', '2026-07-22', 485718.00, '2025-07-31 03:55:24'),
(327, 319, 1, 393, 0, 'BATCH-000319', '2027-04-01', 411482.00, '2025-07-31 03:55:24'),
(328, 320, 2, 312, 0, 'BATCH-000320', '2026-06-21', 707221.00, '2025-07-31 03:55:24'),
(329, 321, 3, 166, 0, 'BATCH-000321', '2026-06-22', 158870.00, '2025-07-31 03:55:24'),
(330, 322, 6, 318, 0, 'BATCH-000322', '2027-06-16', 4119402.00, '2025-07-31 03:55:24'),
(331, 323, 1, 310, 0, 'BATCH-000323', '2027-04-17', 2998540.00, '2025-07-31 03:55:24'),
(332, 324, 7, 521, 0, 'BATCH-000324', '2028-02-20', 4239616.00, '2025-07-31 03:55:24'),
(333, 325, 4, 238, 0, 'BATCH-000325', '2027-08-19', 3218452.00, '2025-07-31 03:55:24'),
(334, 326, 7, 127, 0, 'BATCH-000326', '2026-08-16', 2432359.00, '2025-07-31 03:55:24'),
(335, 327, 1, 467, 0, 'BATCH-000327', '2028-07-15', 16411.00, '2025-07-31 03:55:24'),
(336, 328, 3, 313, 0, 'BATCH-000328', '2028-01-13', 19825.00, '2025-07-31 03:55:24'),
(337, 329, 7, 201, 0, 'BATCH-000329', '2028-08-16', 3382911.00, '2025-07-31 03:55:24'),
(338, 330, 7, 307, 0, 'BATCH-000330', '2028-01-11', 144631.00, '2025-07-31 03:55:24'),
(339, 331, 1, 522, 0, 'BATCH-000331', '2027-12-27', 3004523.00, '2025-07-31 03:55:24'),
(340, 332, 2, 127, 0, 'BATCH-000332', '2026-04-18', 4248375.00, '2025-07-31 03:55:24'),
(341, 333, 4, 306, 0, 'BATCH-000333', '2026-07-08', 1238406.00, '2025-07-31 03:55:24'),
(342, 334, 7, 337, 0, 'BATCH-000334', '2026-09-20', 2066888.00, '2025-07-31 03:55:24'),
(343, 335, 5, 310, 0, 'BATCH-000335', '2028-06-14', 3543732.00, '2025-07-31 03:55:24'),
(344, 336, 3, 168, 0, 'BATCH-000336', '2026-09-14', 1994215.00, '2025-07-31 03:55:24'),
(345, 337, 4, 174, 0, 'BATCH-000337', '2027-12-27', 3385337.00, '2025-07-31 03:55:24'),
(346, 338, 5, 61, 0, 'BATCH-000338', '2026-06-24', 3051263.00, '2025-07-31 03:55:24'),
(347, 339, 7, 372, 0, 'BATCH-000339', '2027-03-24', 783064.00, '2025-07-31 03:55:24'),
(348, 340, 5, 282, 0, 'BATCH-000340', '2027-07-20', 1350505.00, '2025-07-31 03:55:24'),
(349, 341, 7, 288, 0, 'BATCH-000341', '2028-02-27', 1707011.00, '2025-07-31 03:55:24'),
(350, 342, 5, 490, 0, 'BATCH-000342', '2027-09-14', 1525816.00, '2025-07-31 03:55:24'),
(351, 343, 7, 290, 0, 'BATCH-000343', '2028-01-07', 499181.00, '2025-07-31 03:55:24'),
(352, 344, 3, 421, 0, 'BATCH-000344', '2027-05-10', 539957.00, '2025-07-31 03:55:24'),
(353, 345, 2, 333, 0, 'BATCH-000345', '2026-11-04', 3183790.00, '2025-07-31 03:55:24'),
(354, 346, 5, 203, 0, 'BATCH-000346', '2027-05-24', 2215367.00, '2025-07-31 03:55:24'),
(355, 347, 1, 326, 0, 'BATCH-000347', '2028-02-14', 395794.00, '2025-07-31 03:55:24'),
(356, 348, 2, 381, 0, 'BATCH-000348', '2028-02-29', 3724806.00, '2025-07-31 03:55:24'),
(357, 349, 6, 412, 0, 'BATCH-000349', '2026-05-05', 1461066.00, '2025-07-31 03:55:24'),
(358, 350, 3, 359, 0, 'BATCH-000350', '2026-06-18', 3848560.00, '2025-07-31 03:55:24'),
(359, 351, 6, 372, 0, 'BATCH-000351', '2027-12-31', 2621780.00, '2025-07-31 03:55:24'),
(360, 352, 6, 163, 0, 'BATCH-000352', '2028-02-22', 449209.00, '2025-07-31 03:55:24'),
(361, 353, 2, 456, 0, 'BATCH-000353', '2027-03-07', 2626516.00, '2025-07-31 03:55:24'),
(362, 354, 5, 415, 0, 'BATCH-000354', '2027-08-17', 2921228.00, '2025-07-31 03:55:24'),
(363, 355, 4, 411, 0, 'BATCH-000355', '2026-02-13', 4145270.00, '2025-07-31 03:55:24'),
(364, 356, 4, 528, 0, 'BATCH-000356', '2026-07-03', 4120217.00, '2025-07-31 03:55:24'),
(365, 357, 1, 423, 0, 'BATCH-000357', '2027-04-14', 4379520.00, '2025-07-31 03:55:24'),
(366, 358, 4, 416, 0, 'BATCH-000358', '2026-04-14', 849704.00, '2025-07-31 03:55:24'),
(367, 359, 5, 527, 0, 'BATCH-000359', '2027-11-25', 2119277.00, '2025-07-31 03:55:24'),
(368, 360, 3, 207, 0, 'BATCH-000360', '2027-07-25', 3498071.00, '2025-07-31 03:55:24'),
(369, 361, 2, 497, 0, 'BATCH-000361', '2028-02-06', 88797.00, '2025-07-31 03:55:24'),
(370, 362, 7, 194, 0, 'BATCH-000362', '2028-05-17', 1525844.00, '2025-07-31 03:55:24'),
(371, 363, 2, 451, 0, 'BATCH-000363', '2027-07-11', 1083949.00, '2025-07-31 03:55:24'),
(372, 364, 5, 203, 0, 'BATCH-000364', '2028-01-19', 3113239.00, '2025-07-31 03:55:24'),
(373, 365, 2, 221, 0, 'BATCH-000365', '2028-06-15', 1453008.00, '2025-07-31 03:55:24'),
(374, 366, 7, 53, 0, 'BATCH-000366', '2026-03-21', 1121380.00, '2025-07-31 03:55:24'),
(375, 367, 1, 367, 0, 'BATCH-000367', '2028-09-05', 3851664.00, '2025-07-31 03:55:24'),
(376, 368, 3, 303, 0, 'BATCH-000368', '2026-11-13', 4201193.00, '2025-07-31 03:55:24'),
(377, 369, 6, 124, 0, 'BATCH-000369', '2027-02-05', 1936473.00, '2025-07-31 03:55:24'),
(378, 370, 1, 454, 0, 'BATCH-000370', '2028-10-11', 2325692.00, '2025-07-31 03:55:24'),
(379, 371, 5, 302, 0, 'BATCH-000371', '2027-12-20', 4270153.00, '2025-07-31 03:55:24'),
(380, 372, 5, 278, 0, 'BATCH-000372', '2026-11-27', 693511.00, '2025-07-31 03:55:24'),
(381, 373, 6, 442, 0, 'BATCH-000373', '2027-02-08', 2403774.00, '2025-07-31 03:55:24'),
(382, 374, 4, 77, 0, 'BATCH-000374', '2027-12-15', 1232075.00, '2025-07-31 03:55:24'),
(383, 375, 3, 382, 0, 'BATCH-000375', '2027-04-06', 808203.00, '2025-07-31 03:55:24'),
(384, 376, 5, 248, 0, 'BATCH-000376', '2026-09-14', 4327711.00, '2025-07-31 03:55:24'),
(385, 377, 1, 378, 0, 'BATCH-000377', '2028-09-18', 3852319.00, '2025-07-31 03:55:24'),
(386, 378, 3, 206, 0, 'BATCH-000378', '2027-04-13', 1212881.00, '2025-07-31 03:55:24'),
(387, 379, 1, 182, 0, 'BATCH-000379', '2026-11-10', 2892267.00, '2025-07-31 03:55:24'),
(388, 380, 3, 442, 0, 'BATCH-000380', '2028-07-17', 716387.00, '2025-07-31 03:55:24'),
(389, 381, 1, 510, 0, 'BATCH-000381', '2027-01-30', 359222.00, '2025-07-31 03:55:24'),
(390, 382, 3, 147, 0, 'BATCH-000382', '2026-05-28', 97777.00, '2025-07-31 03:55:24'),
(391, 383, 6, 357, 0, 'BATCH-000383', '2028-06-18', 2352634.00, '2025-07-31 03:55:24'),
(392, 384, 7, 228, 0, 'BATCH-000384', '2028-05-09', 445673.00, '2025-07-31 03:55:24'),
(393, 385, 7, 366, 0, 'BATCH-000385', '2026-08-26', 714348.00, '2025-07-31 03:55:24'),
(394, 386, 2, 191, 0, 'BATCH-000386', '2028-09-14', 4334021.00, '2025-07-31 03:55:24'),
(395, 387, 7, 409, 0, 'BATCH-000387', '2028-05-12', 118907.00, '2025-07-31 03:55:24'),
(396, 388, 5, 544, 0, 'BATCH-000388', '2026-05-17', 2641569.00, '2025-07-31 03:55:24'),
(397, 389, 5, 155, 0, 'BATCH-000389', '2026-10-28', 3338873.00, '2025-07-31 03:55:24'),
(398, 390, 7, 132, 0, 'BATCH-000390', '2026-08-10', 2178213.00, '2025-07-31 03:55:24'),
(399, 391, 6, 386, 0, 'BATCH-000391', '2028-07-11', 2090406.00, '2025-07-31 03:55:24'),
(400, 392, 5, 413, 0, 'BATCH-000392', '2028-03-05', 2985942.00, '2025-07-31 03:55:24'),
(401, 393, 1, 62, 0, 'BATCH-000393', '2026-05-21', 2267189.00, '2025-07-31 03:55:24'),
(402, 394, 2, 210, 0, 'BATCH-000394', '2026-05-19', 2696645.00, '2025-07-31 03:55:24'),
(403, 395, 5, 277, 0, 'BATCH-000395', '2026-12-19', 1219072.00, '2025-07-31 03:55:24'),
(404, 396, 3, 58, 0, 'BATCH-000396', '2028-10-16', 4125438.00, '2025-07-31 03:55:24'),
(405, 397, 5, 162, 0, 'BATCH-000397', '2027-01-05', 192329.00, '2025-07-31 03:55:24'),
(406, 398, 2, 426, 0, 'BATCH-000398', '2026-09-22', 4220387.00, '2025-07-31 03:55:24'),
(407, 399, 7, 54, 0, 'BATCH-000399', '2026-07-03', 3426018.00, '2025-07-31 03:55:24'),
(408, 400, 3, 222, 0, 'BATCH-000400', '2028-02-13', 3184850.00, '2025-07-31 03:55:24'),
(409, 401, 3, 207, 0, 'BATCH-000401', '2028-01-10', 2808196.00, '2025-07-31 03:55:24'),
(410, 402, 7, 546, 0, 'BATCH-000402', '2026-03-14', 1150368.00, '2025-07-31 03:55:24'),
(411, 403, 1, 496, 0, 'BATCH-000403', '2026-04-06', 3024350.00, '2025-07-31 03:55:24'),
(412, 404, 2, 402, 0, 'BATCH-000404', '2026-04-29', 1584334.00, '2025-07-31 03:55:24'),
(413, 405, 4, 208, 0, 'BATCH-000405', '2026-07-07', 3866235.00, '2025-07-31 03:55:24'),
(414, 406, 6, 271, 0, 'BATCH-000406', '2028-04-13', 3199438.00, '2025-07-31 03:55:24'),
(415, 407, 1, 291, 0, 'BATCH-000407', '2026-03-20', 3654133.00, '2025-07-31 03:55:24'),
(416, 408, 7, 70, 0, 'BATCH-000408', '2027-06-29', 2125043.00, '2025-07-31 03:55:24'),
(417, 409, 6, 338, 0, 'BATCH-000409', '2027-06-04', 3317052.00, '2025-07-31 03:55:24'),
(418, 410, 2, 437, 0, 'BATCH-000410', '2026-11-11', 532403.00, '2025-07-31 03:55:24'),
(419, 411, 6, 167, 0, 'BATCH-000411', '2026-02-18', 1844904.00, '2025-07-31 03:55:24'),
(420, 412, 7, 372, 0, 'BATCH-000412', '2026-11-24', 2589441.00, '2025-07-31 03:55:24'),
(421, 413, 7, 98, 0, 'BATCH-000413', '2027-09-17', 3153173.00, '2025-07-31 03:55:24'),
(422, 414, 5, 248, 0, 'BATCH-000414', '2028-07-06', 1205617.00, '2025-07-31 03:55:24'),
(423, 415, 5, 288, 0, 'BATCH-000415', '2027-03-23', 3031637.00, '2025-07-31 03:55:24'),
(424, 416, 1, 285, 0, 'BATCH-000416', '2026-04-02', 4108498.00, '2025-07-31 03:55:24'),
(425, 417, 3, 84, 0, 'BATCH-000417', '2026-10-20', 564201.00, '2025-07-31 03:55:24'),
(426, 418, 6, 410, 0, 'BATCH-000418', '2026-06-25', 2644573.00, '2025-07-31 03:55:24'),
(427, 419, 4, 371, 0, 'BATCH-000419', '2028-03-13', 4300443.00, '2025-07-31 03:55:24'),
(428, 420, 4, 215, 0, 'BATCH-000420', '2027-01-05', 3253535.00, '2025-07-31 03:55:24'),
(429, 421, 5, 408, 0, 'BATCH-000421', '2028-05-29', 538568.00, '2025-07-31 03:55:24'),
(430, 422, 1, 446, 0, 'BATCH-000422', '2028-06-25', 104448.00, '2025-07-31 03:55:24'),
(431, 423, 4, 181, 0, 'BATCH-000423', '2028-08-01', 3613640.00, '2025-07-31 03:55:24'),
(432, 424, 2, 479, 0, 'BATCH-000424', '2027-07-14', 430446.00, '2025-07-31 03:55:24'),
(433, 425, 7, 80, 0, 'BATCH-000425', '2027-12-23', 1350012.00, '2025-07-31 03:55:24'),
(434, 426, 3, 112, 0, 'BATCH-000426', '2027-03-15', 3099905.00, '2025-07-31 03:55:24'),
(435, 427, 2, 515, 0, 'BATCH-000427', '2026-03-30', 2328457.00, '2025-07-31 03:55:24'),
(436, 428, 3, 256, 0, 'BATCH-000428', '2028-07-06', 980481.00, '2025-07-31 03:55:24'),
(437, 429, 3, 242, 0, 'BATCH-000429', '2027-12-29', 1611868.00, '2025-07-31 03:55:24'),
(438, 430, 5, 206, 0, 'BATCH-000430', '2027-07-18', 3363798.00, '2025-07-31 03:55:24'),
(439, 431, 1, 224, 0, 'BATCH-000431', '2027-02-23', 4133571.00, '2025-07-31 03:55:24'),
(440, 432, 3, 189, 0, 'BATCH-000432', '2026-07-24', 259325.00, '2025-07-31 03:55:24'),
(441, 433, 6, 323, 0, 'BATCH-000433', '2027-06-18', 4041235.00, '2025-07-31 03:55:24'),
(442, 434, 7, 101, 0, 'BATCH-000434', '2027-10-30', 4050216.00, '2025-07-31 03:55:24'),
(443, 435, 4, 118, 0, 'BATCH-000435', '2028-10-06', 2296083.00, '2025-07-31 03:55:24'),
(444, 436, 5, 266, 0, 'BATCH-000436', '2027-02-19', 2900912.00, '2025-07-31 03:55:24'),
(445, 437, 1, 210, 0, 'BATCH-000437', '2027-04-28', 1442277.00, '2025-07-31 03:55:24'),
(446, 438, 2, 132, 0, 'BATCH-000438', '2026-06-24', 1139268.00, '2025-07-31 03:55:24'),
(447, 439, 6, 199, 0, 'BATCH-000439', '2026-03-29', 1856334.00, '2025-07-31 03:55:24'),
(448, 440, 7, 108, 0, 'BATCH-000440', '2028-09-27', 2353808.00, '2025-07-31 03:55:24'),
(449, 441, 5, 476, 0, 'BATCH-000441', '2026-09-02', 2405005.00, '2025-07-31 03:55:24'),
(450, 442, 1, 267, 0, 'BATCH-000442', '2026-07-03', 2170484.00, '2025-07-31 03:55:24'),
(451, 443, 7, 155, 0, 'BATCH-000443', '2026-10-17', 3082553.00, '2025-07-31 03:55:24'),
(452, 444, 5, 91, 0, 'BATCH-000444', '2027-07-15', 1918644.00, '2025-07-31 03:55:24'),
(453, 445, 4, 210, 0, 'BATCH-000445', '2026-03-19', 1320081.00, '2025-07-31 03:55:24'),
(454, 446, 3, 372, 0, 'BATCH-000446', '2026-12-03', 2789678.00, '2025-07-31 03:55:24'),
(455, 447, 2, 522, 0, 'BATCH-000447', '2026-10-03', 1845133.00, '2025-07-31 03:55:24'),
(456, 448, 3, 171, 0, 'BATCH-000448', '2026-12-31', 4328805.00, '2025-07-31 03:55:24'),
(457, 449, 6, 74, 0, 'BATCH-000449', '2028-06-28', 1236292.00, '2025-07-31 03:55:24'),
(458, 450, 6, 426, 0, 'BATCH-000450', '2027-10-10', 3827007.00, '2025-07-31 03:55:24'),
(459, 451, 3, 224, 0, 'BATCH-000451', '2027-09-24', 4435652.00, '2025-07-31 03:55:24'),
(460, 452, 1, 328, 0, 'BATCH-000452', '2027-05-25', 3353046.00, '2025-07-31 03:55:24'),
(461, 453, 2, 101, 0, 'BATCH-000453', '2028-01-12', 1219049.00, '2025-07-31 03:55:24'),
(462, 454, 2, 142, 0, 'BATCH-000454', '2026-12-23', 448985.00, '2025-07-31 03:55:24'),
(463, 455, 4, 147, 0, 'BATCH-000455', '2027-05-21', 3670884.00, '2025-07-31 03:55:24'),
(464, 456, 5, 407, 0, 'BATCH-000456', '2027-12-07', 1157352.00, '2025-07-31 03:55:24'),
(465, 457, 2, 259, 0, 'BATCH-000457', '2027-02-17', 3042327.00, '2025-07-31 03:55:24'),
(466, 458, 2, 67, 0, 'BATCH-000458', '2027-07-20', 2684664.00, '2025-07-31 03:55:24'),
(467, 459, 3, 543, 0, 'BATCH-000459', '2028-06-18', 1823423.00, '2025-07-31 03:55:24'),
(468, 460, 3, 440, 0, 'BATCH-000460', '2028-01-04', 888452.00, '2025-07-31 03:55:24'),
(469, 461, 6, 397, 0, 'BATCH-000461', '2028-07-18', 1953794.00, '2025-07-31 03:55:24'),
(470, 462, 4, 533, 0, 'BATCH-000462', '2027-05-14', 2098919.00, '2025-07-31 03:55:24'),
(471, 463, 7, 116, 0, 'BATCH-000463', '2028-09-02', 1583893.00, '2025-07-31 03:55:24'),
(472, 464, 7, 277, 0, 'BATCH-000464', '2027-08-18', 2174816.00, '2025-07-31 03:55:24'),
(473, 465, 5, 79, 0, 'BATCH-000465', '2026-08-09', 3578651.00, '2025-07-31 03:55:24'),
(474, 466, 3, 321, 0, 'BATCH-000466', '2027-08-07', 729143.00, '2025-07-31 03:55:24'),
(475, 467, 1, 132, 0, 'BATCH-000467', '2027-04-10', 3137290.00, '2025-07-31 03:55:24'),
(476, 468, 2, 413, 0, 'BATCH-000468', '2026-06-19', 2441827.00, '2025-07-31 03:55:24'),
(477, 469, 2, 419, 0, 'BATCH-000469', '2028-06-25', 838210.00, '2025-07-31 03:55:24'),
(478, 470, 2, 474, 0, 'BATCH-000470', '2027-03-06', 2130002.00, '2025-07-31 03:55:24'),
(479, 471, 2, 209, 0, 'BATCH-000471', '2026-06-26', 3607594.00, '2025-07-31 03:55:24'),
(480, 472, 4, 217, 0, 'BATCH-000472', '2026-03-03', 786529.00, '2025-07-31 03:55:24'),
(481, 473, 6, 184, 0, 'BATCH-000473', '2026-04-07', 2476522.00, '2025-07-31 03:55:24'),
(482, 474, 4, 52, 0, 'BATCH-000474', '2027-04-03', 650298.00, '2025-07-31 03:55:24'),
(483, 475, 3, 387, 0, 'BATCH-000475', '2026-05-16', 2365784.00, '2025-07-31 03:55:24'),
(484, 476, 3, 493, 0, 'BATCH-000476', '2027-08-13', 702004.00, '2025-07-31 03:55:24'),
(485, 477, 1, 519, 0, 'BATCH-000477', '2027-04-27', 2070862.00, '2025-07-31 03:55:24'),
(486, 478, 7, 178, 0, 'BATCH-000478', '2027-06-13', 3355489.00, '2025-07-31 03:55:24'),
(487, 479, 2, 463, 0, 'BATCH-000479', '2027-06-11', 105029.00, '2025-07-31 03:55:24'),
(488, 480, 5, 532, 0, 'BATCH-000480', '2026-02-03', 642252.00, '2025-07-31 03:55:24'),
(489, 481, 5, 546, 0, 'BATCH-000481', '2028-07-30', 2697187.00, '2025-07-31 03:55:24'),
(490, 482, 2, 258, 0, 'BATCH-000482', '2027-01-24', 2524872.00, '2025-07-31 03:55:24'),
(491, 483, 5, 483, 0, 'BATCH-000483', '2026-08-22', 1971088.00, '2025-07-31 03:55:24'),
(492, 484, 4, 293, 0, 'BATCH-000484', '2028-02-23', 1480637.00, '2025-07-31 03:55:24'),
(493, 485, 3, 467, 0, 'BATCH-000485', '2026-04-20', 4112258.00, '2025-07-31 03:55:24'),
(494, 486, 3, 458, 0, 'BATCH-000486', '2026-07-02', 1485069.00, '2025-07-31 03:55:24'),
(495, 487, 2, 488, 0, 'BATCH-000487', '2028-06-12', 3197647.00, '2025-07-31 03:55:24'),
(496, 488, 7, 337, 0, 'BATCH-000488', '2026-03-19', 2414485.00, '2025-07-31 03:55:24'),
(497, 489, 4, 545, 0, 'BATCH-000489', '2027-02-28', 70810.00, '2025-07-31 03:55:24'),
(498, 490, 7, 223, 0, 'BATCH-000490', '2026-05-09', 2126743.00, '2025-07-31 03:55:24'),
(499, 491, 1, 460, 0, 'BATCH-000491', '2028-09-18', 1649173.00, '2025-07-31 03:55:24'),
(500, 492, 7, 319, 0, 'BATCH-000492', '2028-07-29', 4312221.00, '2025-07-31 03:55:24'),
(501, 493, 1, 211, 0, 'BATCH-000493', '2027-06-12', 2420790.00, '2025-07-31 03:55:24'),
(502, 494, 2, 188, 0, 'BATCH-000494', '2028-05-28', 1953191.00, '2025-07-31 03:55:24'),
(503, 495, 5, 411, 0, 'BATCH-000495', '2028-04-06', 3772644.00, '2025-07-31 03:55:24'),
(504, 496, 6, 246, 0, 'BATCH-000496', '2027-10-11', 4220361.00, '2025-07-31 03:55:24'),
(505, 497, 6, 174, 0, 'BATCH-000497', '2028-04-17', 1411660.00, '2025-07-31 03:55:24'),
(506, 498, 1, 391, 0, 'BATCH-000498', '2026-03-11', 762158.00, '2025-07-31 03:55:24'),
(507, 499, 5, 69, 0, 'BATCH-000499', '2026-04-03', 987701.00, '2025-07-31 03:55:24'),
(508, 500, 7, 446, 0, 'BATCH-000500', '2026-11-18', 458695.00, '2025-07-31 03:55:24'),
(509, 501, 5, 434, 0, 'BATCH-000501', '2026-02-01', 3240587.00, '2025-07-31 03:55:24'),
(510, 502, 5, 411, 0, 'BATCH-000502', '2028-07-05', 1279032.00, '2025-07-31 03:55:24'),
(511, 503, 6, 477, 0, 'BATCH-000503', '2026-03-19', 3132432.00, '2025-07-31 03:55:24'),
(512, 504, 3, 300, 0, 'BATCH-000504', '2027-08-05', 1234735.00, '2025-07-31 03:55:24'),
(513, 505, 5, 384, 0, 'BATCH-000505', '2026-10-08', 1199238.00, '2025-07-31 03:55:24'),
(514, 506, 4, 52, 0, 'BATCH-000506', '2027-01-08', 3237009.00, '2025-07-31 03:55:24'),
(515, 507, 4, 343, 0, 'BATCH-000507', '2026-11-10', 3067850.00, '2025-07-31 03:55:24'),
(516, 508, 4, 371, 0, 'BATCH-000508', '2027-09-26', 486917.00, '2025-07-31 03:55:24'),
(517, 509, 5, 165, 0, 'BATCH-000509', '2026-02-19', 1928757.00, '2025-07-31 03:55:24'),
(518, 510, 1, 66, 0, 'BATCH-000510', '2028-09-29', 3535316.00, '2025-07-31 03:55:24'),
(519, 511, 7, 348, 0, 'BATCH-000511', '2026-02-11', 1296159.00, '2025-07-31 03:55:24'),
(520, 512, 3, 83, 0, 'BATCH-000512', '2026-07-25', 3133877.00, '2025-07-31 03:55:24'),
(521, 513, 7, 348, 0, 'BATCH-000513', '2026-07-18', 342873.00, '2025-07-31 03:55:24'),
(522, 514, 6, 74, 0, 'BATCH-000514', '2027-12-09', 1173612.00, '2025-07-31 03:55:24'),
(523, 515, 2, 290, 0, 'BATCH-000515', '2027-11-10', 3688237.00, '2025-07-31 03:55:24'),
(524, 516, 1, 152, 0, 'BATCH-000516', '2027-10-18', 2414747.00, '2025-07-31 03:55:24'),
(525, 517, 6, 208, 0, 'BATCH-000517', '2026-09-14', 923047.00, '2025-07-31 03:55:24'),
(526, 518, 3, 56, 0, 'BATCH-000518', '2026-04-30', 1922496.00, '2025-07-31 03:55:24'),
(527, 519, 6, 531, 0, 'BATCH-000519', '2026-10-22', 2061294.00, '2025-07-31 03:55:24'),
(528, 520, 4, 54, 0, 'BATCH-000520', '2027-10-02', 213657.00, '2025-07-31 03:55:24'),
(529, 521, 3, 448, 0, 'BATCH-000521', '2028-04-26', 3231673.00, '2025-07-31 03:55:24'),
(530, 522, 1, 272, 0, 'BATCH-000522', '2028-06-14', 69734.00, '2025-07-31 03:55:24'),
(531, 523, 4, 176, 0, 'BATCH-000523', '2028-07-02', 3065156.00, '2025-07-31 03:55:24'),
(532, 524, 6, 366, 0, 'BATCH-000524', '2028-09-15', 4112103.00, '2025-07-31 03:55:24'),
(533, 525, 5, 365, 0, 'BATCH-000525', '2026-06-14', 3585598.00, '2025-07-31 03:55:24'),
(534, 526, 4, 259, 0, 'BATCH-000526', '2027-03-18', 3691811.00, '2025-07-31 03:55:24'),
(535, 527, 6, 438, 0, 'BATCH-000527', '2027-01-06', 1769940.00, '2025-07-31 03:55:24'),
(536, 528, 7, 274, 0, 'BATCH-000528', '2027-05-08', 4464750.00, '2025-07-31 03:55:24'),
(537, 529, 4, 442, 0, 'BATCH-000529', '2026-10-22', 4456304.00, '2025-07-31 03:55:24'),
(538, 530, 1, 411, 0, 'BATCH-000530', '2026-08-16', 3779626.00, '2025-07-31 03:55:24'),
(539, 531, 5, 259, 0, 'BATCH-000531', '2026-12-26', 1863062.00, '2025-07-31 03:55:24'),
(540, 532, 1, 82, 0, 'BATCH-000532', '2026-06-15', 2292503.00, '2025-07-31 03:55:24'),
(541, 533, 1, 84, 0, 'BATCH-000533', '2028-10-12', 3332431.00, '2025-07-31 03:55:24'),
(542, 534, 6, 258, 0, 'BATCH-000534', '2028-07-20', 1243182.00, '2025-07-31 03:55:24'),
(543, 535, 5, 281, 0, 'BATCH-000535', '2026-12-31', 1396386.00, '2025-07-31 03:55:24'),
(544, 536, 4, 401, 0, 'BATCH-000536', '2028-08-24', 2674758.00, '2025-07-31 03:55:24'),
(545, 537, 1, 513, 0, 'BATCH-000537', '2026-08-26', 1246808.00, '2025-07-31 03:55:24'),
(546, 538, 6, 494, 0, 'BATCH-000538', '2026-09-02', 1911843.00, '2025-07-31 03:55:24'),
(547, 539, 4, 66, 0, 'BATCH-000539', '2028-03-20', 3682721.00, '2025-07-31 03:55:24'),
(548, 540, 6, 159, 0, 'BATCH-000540', '2028-07-12', 3726107.00, '2025-07-31 03:55:24'),
(549, 541, 4, 410, 0, 'BATCH-000541', '2026-11-06', 1166286.00, '2025-07-31 03:55:24'),
(550, 542, 4, 252, 0, 'BATCH-000542', '2028-01-11', 1633560.00, '2025-07-31 03:55:24'),
(551, 543, 5, 163, 0, 'BATCH-000543', '2026-06-22', 253866.00, '2025-07-31 03:55:24'),
(552, 544, 6, 549, 0, 'BATCH-000544', '2027-06-06', 2169622.00, '2025-07-31 03:55:24'),
(553, 545, 7, 120, 0, 'BATCH-000545', '2028-09-04', 1529264.00, '2025-07-31 03:55:24'),
(554, 546, 6, 131, 0, 'BATCH-000546', '2026-11-29', 210161.00, '2025-07-31 03:55:24'),
(555, 547, 3, 245, 0, 'BATCH-000547', '2026-03-07', 126859.00, '2025-07-31 03:55:24'),
(556, 548, 1, 541, 0, 'BATCH-000548', '2028-06-18', 1901658.00, '2025-07-31 03:55:24'),
(557, 549, 4, 128, 0, 'BATCH-000549', '2026-12-27', 905279.00, '2025-07-31 03:55:24'),
(558, 550, 7, 236, 0, 'BATCH-000550', '2028-06-30', 1388541.00, '2025-07-31 03:55:24'),
(559, 551, 7, 282, 0, 'BATCH-000551', '2027-12-22', 353851.00, '2025-07-31 03:55:24'),
(560, 552, 3, 186, 0, 'BATCH-000552', '2027-05-08', 2311071.00, '2025-07-31 03:55:24'),
(561, 553, 2, 179, 0, 'BATCH-000553', '2028-04-25', 1447512.00, '2025-07-31 03:55:24'),
(562, 554, 1, 422, 0, 'BATCH-000554', '2026-11-23', 1211780.00, '2025-07-31 03:55:24'),
(563, 555, 4, 240, 0, 'BATCH-000555', '2027-09-16', 3804092.00, '2025-07-31 03:55:24'),
(564, 556, 3, 346, 0, 'BATCH-000556', '2027-12-19', 3061377.00, '2025-07-31 03:55:24'),
(565, 557, 3, 326, 0, 'BATCH-000557', '2028-04-19', 1832756.00, '2025-07-31 03:55:24'),
(566, 558, 5, 412, 0, 'BATCH-000558', '2028-06-05', 575752.00, '2025-07-31 03:55:24'),
(567, 559, 1, 485, 0, 'BATCH-000559', '2026-08-24', 1941794.00, '2025-07-31 03:55:24'),
(568, 560, 4, 209, 0, 'BATCH-000560', '2026-02-22', 811301.00, '2025-07-31 03:55:24'),
(569, 561, 6, 313, 0, 'BATCH-000561', '2026-08-15', 1902922.00, '2025-07-31 03:55:24'),
(570, 562, 4, 175, 0, 'BATCH-000562', '2028-02-11', 4399048.00, '2025-07-31 03:55:24'),
(571, 563, 5, 191, 0, 'BATCH-000563', '2027-05-28', 2648937.00, '2025-07-31 03:55:24'),
(572, 564, 4, 353, 0, 'BATCH-000564', '2027-10-05', 1174491.00, '2025-07-31 03:55:24'),
(573, 565, 4, 279, 0, 'BATCH-000565', '2028-09-03', 1698495.00, '2025-07-31 03:55:24'),
(574, 566, 1, 56, 0, 'BATCH-000566', '2028-10-01', 3862012.00, '2025-07-31 03:55:24'),
(575, 567, 3, 130, 0, 'BATCH-000567', '2028-02-28', 1504046.00, '2025-07-31 03:55:24'),
(576, 568, 3, 488, 0, 'BATCH-000568', '2026-10-11', 2976819.00, '2025-07-31 03:55:24'),
(577, 569, 4, 373, 0, 'BATCH-000569', '2027-11-18', 1633276.00, '2025-07-31 03:55:24'),
(578, 570, 6, 68, 0, 'BATCH-000570', '2028-01-07', 2003387.00, '2025-07-31 03:55:24'),
(579, 571, 1, 98, 0, 'BATCH-000571', '2026-09-09', 3778367.00, '2025-07-31 03:55:24'),
(580, 572, 4, 76, 0, 'BATCH-000572', '2028-01-22', 2117626.00, '2025-07-31 03:55:24'),
(581, 573, 2, 264, 0, 'BATCH-000573', '2027-11-02', 4209895.00, '2025-07-31 03:55:24'),
(582, 574, 6, 489, 0, 'BATCH-000574', '2026-08-03', 1378396.00, '2025-07-31 03:55:24'),
(583, 575, 7, 485, 0, 'BATCH-000575', '2027-05-29', 3700482.00, '2025-07-31 03:55:24'),
(584, 576, 5, 422, 0, 'BATCH-000576', '2028-04-09', 3527137.00, '2025-07-31 03:55:24'),
(585, 577, 4, 123, 0, 'BATCH-000577', '2026-09-27', 3481043.00, '2025-07-31 03:55:24'),
(586, 578, 1, 216, 0, 'BATCH-000578', '2026-10-29', 1711824.00, '2025-07-31 03:55:24'),
(587, 579, 1, 149, 0, 'BATCH-000579', '2028-03-26', 1603275.00, '2025-07-31 03:55:24'),
(588, 580, 3, 526, 0, 'BATCH-000580', '2027-08-07', 4177669.00, '2025-07-31 03:55:24'),
(589, 581, 7, 61, 0, 'BATCH-000581', '2026-09-19', 487227.00, '2025-07-31 03:55:24'),
(590, 582, 6, 456, 0, 'BATCH-000582', '2027-09-01', 2139760.00, '2025-07-31 03:55:24'),
(591, 583, 5, 395, 0, 'BATCH-000583', '2027-09-05', 3884197.00, '2025-07-31 03:55:24'),
(592, 584, 4, 124, 0, 'BATCH-000584', '2026-05-12', 371143.00, '2025-07-31 03:55:24'),
(593, 585, 1, 145, 0, 'BATCH-000585', '2027-12-24', 4094216.00, '2025-07-31 03:55:24'),
(594, 586, 4, 315, 0, 'BATCH-000586', '2026-11-26', 4165418.00, '2025-07-31 03:55:24'),
(595, 587, 5, 435, 0, 'BATCH-000587', '2028-01-26', 1518791.00, '2025-07-31 03:55:24'),
(596, 588, 4, 269, 0, 'BATCH-000588', '2028-01-24', 1458555.00, '2025-07-31 03:55:24'),
(597, 589, 3, 136, 0, 'BATCH-000589', '2027-08-27', 1674177.00, '2025-07-31 03:55:24'),
(598, 590, 1, 292, 0, 'BATCH-000590', '2026-04-06', 4011972.00, '2025-07-31 03:55:24');
INSERT INTO `stock_inventory` (`id`, `product_id`, `location_id`, `quantity`, `reserved_quantity`, `batch_number`, `expiry_date`, `cost_per_unit`, `last_updated`) VALUES
(599, 591, 2, 318, 0, 'BATCH-000591', '2028-09-15', 910140.00, '2025-07-31 03:55:24'),
(600, 592, 1, 536, 0, 'BATCH-000592', '2027-07-03', 3120164.00, '2025-07-31 03:55:24'),
(601, 593, 7, 239, 0, 'BATCH-000593', '2026-09-06', 4406943.00, '2025-07-31 03:55:24'),
(602, 594, 2, 130, 0, 'BATCH-000594', '2026-06-28', 1260186.00, '2025-07-31 03:55:24'),
(603, 595, 7, 464, 0, 'BATCH-000595', '2027-01-12', 1193588.00, '2025-07-31 03:55:24'),
(604, 596, 2, 318, 0, 'BATCH-000596', '2028-07-02', 3737751.00, '2025-07-31 03:55:24'),
(605, 597, 4, 508, 0, 'BATCH-000597', '2026-06-15', 4280122.00, '2025-07-31 03:55:24'),
(606, 598, 3, 445, 0, 'BATCH-000598', '2028-09-26', 2235960.00, '2025-07-31 03:55:24'),
(607, 599, 4, 191, 0, 'BATCH-000599', '2028-02-20', 4156571.00, '2025-07-31 03:55:24'),
(608, 600, 3, 534, 0, 'BATCH-000600', '2028-04-09', 503172.00, '2025-07-31 03:55:24'),
(609, 601, 1, 235, 0, 'BATCH-000601', '2027-04-08', 317935.00, '2025-07-31 03:55:24'),
(610, 602, 1, 532, 0, 'BATCH-000602', '2028-01-18', 3206603.00, '2025-07-31 03:55:24'),
(611, 603, 3, 461, 0, 'BATCH-000603', '2028-08-22', 1024076.00, '2025-07-31 03:55:24'),
(612, 604, 3, 494, 0, 'BATCH-000604', '2027-06-19', 3935431.00, '2025-07-31 03:55:24'),
(613, 605, 6, 337, 0, 'BATCH-000605', '2027-01-20', 314705.00, '2025-07-31 03:55:24'),
(614, 606, 2, 110, 0, 'BATCH-000606', '2028-04-15', 3086016.00, '2025-07-31 03:55:24'),
(615, 607, 7, 503, 0, 'BATCH-000607', '2027-08-13', 424512.00, '2025-07-31 03:55:24'),
(616, 608, 6, 344, 0, 'BATCH-000608', '2027-10-10', 1552387.00, '2025-07-31 03:55:24'),
(617, 609, 6, 163, 0, 'BATCH-000609', '2027-08-29', 995165.00, '2025-07-31 03:55:24'),
(618, 610, 3, 113, 0, 'BATCH-000610', '2027-08-15', 2010482.00, '2025-07-31 03:55:24'),
(619, 611, 4, 204, 0, 'BATCH-000611', '2028-09-11', 3899122.00, '2025-07-31 03:55:24'),
(620, 612, 4, 374, 0, 'BATCH-000612', '2028-07-13', 2461873.00, '2025-07-31 03:55:24'),
(621, 613, 1, 310, 0, 'BATCH-000613', '2027-06-23', 4505442.00, '2025-07-31 03:55:24'),
(622, 614, 4, 198, 0, 'BATCH-000614', '2026-05-11', 2867097.00, '2025-07-31 03:55:24'),
(623, 615, 7, 252, 0, 'BATCH-000615', '2027-04-09', 4385353.00, '2025-07-31 03:55:24'),
(624, 616, 4, 469, 0, 'BATCH-000616', '2027-07-22', 853200.00, '2025-07-31 03:55:24'),
(625, 617, 3, 58, 0, 'BATCH-000617', '2026-06-12', 2846187.00, '2025-07-31 03:55:24'),
(626, 618, 6, 465, 0, 'BATCH-000618', '2028-08-06', 544827.00, '2025-07-31 03:55:24'),
(627, 619, 6, 442, 0, 'BATCH-000619', '2027-04-08', 3746512.00, '2025-07-31 03:55:24'),
(628, 620, 6, 412, 0, 'BATCH-000620', '2026-04-30', 1334652.00, '2025-07-31 03:55:24'),
(629, 621, 2, 88, 0, 'BATCH-000621', '2028-04-18', 3730283.00, '2025-07-31 03:55:24'),
(630, 622, 5, 57, 0, 'BATCH-000622', '2028-09-30', 3792241.00, '2025-07-31 03:55:24'),
(631, 623, 2, 471, 0, 'BATCH-000623', '2027-02-25', 1997810.00, '2025-07-31 03:55:24'),
(632, 624, 1, 458, 0, 'BATCH-000624', '2026-01-27', 2489179.00, '2025-07-31 03:55:24'),
(633, 625, 6, 109, 0, 'BATCH-000625', '2026-12-25', 1377900.00, '2025-07-31 03:55:24'),
(634, 626, 4, 405, 0, 'BATCH-000626', '2028-09-30', 3408379.00, '2025-07-31 03:55:24'),
(635, 627, 6, 532, 0, 'BATCH-000627', '2026-11-06', 2376065.00, '2025-07-31 03:55:24'),
(636, 628, 6, 208, 0, 'BATCH-000628', '2026-10-02', 1323649.00, '2025-07-31 03:55:24'),
(637, 629, 6, 399, 0, 'BATCH-000629', '2027-01-12', 2962259.00, '2025-07-31 03:55:24'),
(638, 630, 2, 139, 0, 'BATCH-000630', '2026-08-22', 2251501.00, '2025-07-31 03:55:24'),
(639, 631, 7, 479, 0, 'BATCH-000631', '2027-12-08', 3733800.00, '2025-07-31 03:55:24'),
(640, 632, 1, 51, 0, 'BATCH-000632', '2028-01-19', 2733936.00, '2025-07-31 03:55:24'),
(641, 633, 7, 291, 0, 'BATCH-000633', '2028-05-07', 3214259.00, '2025-07-31 03:55:24'),
(642, 634, 1, 148, 0, 'BATCH-000634', '2028-03-19', 1454083.00, '2025-07-31 03:55:24'),
(643, 635, 2, 218, 0, 'BATCH-000635', '2028-07-19', 2307586.00, '2025-07-31 03:55:24'),
(644, 636, 6, 388, 0, 'BATCH-000636', '2028-05-31', 1133151.00, '2025-07-31 03:55:24'),
(645, 637, 5, 382, 0, 'BATCH-000637', '2026-10-26', 1668260.00, '2025-07-31 03:55:24'),
(646, 638, 1, 66, 0, 'BATCH-000638', '2026-04-15', 1339922.00, '2025-07-31 03:55:24'),
(647, 639, 2, 215, 0, 'BATCH-000639', '2028-08-10', 2876269.00, '2025-07-31 03:55:24'),
(648, 640, 3, 112, 0, 'BATCH-000640', '2027-03-08', 2938607.00, '2025-07-31 03:55:24'),
(649, 641, 1, 171, 0, 'BATCH-000641', '2026-05-02', 3376312.00, '2025-07-31 03:55:24'),
(650, 642, 4, 69, 0, 'BATCH-000642', '2028-04-26', 4459845.00, '2025-07-31 03:55:24'),
(651, 643, 4, 276, 0, 'BATCH-000643', '2028-04-17', 3157781.00, '2025-07-31 03:55:24'),
(652, 644, 1, 161, 0, 'BATCH-000644', '2028-08-08', 4283380.00, '2025-07-31 03:55:24'),
(653, 645, 7, 69, 0, 'BATCH-000645', '2026-10-13', 831001.00, '2025-07-31 03:55:24'),
(654, 646, 1, 113, 0, 'BATCH-000646', '2026-09-15', 3491689.00, '2025-07-31 03:55:24'),
(655, 647, 2, 331, 0, 'BATCH-000647', '2026-11-04', 3250149.00, '2025-07-31 03:55:24'),
(656, 648, 6, 363, 0, 'BATCH-000648', '2028-06-04', 1886362.00, '2025-07-31 03:55:24'),
(657, 649, 4, 196, 0, 'BATCH-000649', '2028-08-22', 3672237.00, '2025-07-31 03:55:24'),
(658, 650, 2, 466, 0, 'BATCH-000650', '2027-02-27', 2193984.00, '2025-07-31 03:55:24'),
(659, 651, 2, 419, 0, 'BATCH-000651', '2028-09-29', 2997342.00, '2025-07-31 03:55:24'),
(660, 652, 3, 536, 0, 'BATCH-000652', '2027-12-13', 2287557.00, '2025-07-31 03:55:24'),
(661, 653, 4, 484, 0, 'BATCH-000653', '2028-07-25', 4259243.00, '2025-07-31 03:55:24'),
(662, 654, 7, 116, 0, 'BATCH-000654', '2027-12-08', 40394.00, '2025-07-31 03:55:24'),
(663, 655, 7, 523, 0, 'BATCH-000655', '2028-02-24', 4268527.00, '2025-07-31 03:55:24'),
(664, 656, 4, 278, 0, 'BATCH-000656', '2028-07-22', 744820.00, '2025-07-31 03:55:24'),
(665, 657, 1, 548, 0, 'BATCH-000657', '2027-12-20', 2134487.00, '2025-07-31 03:55:24'),
(666, 658, 2, 51, 0, 'BATCH-000658', '2026-07-12', 3710849.00, '2025-07-31 03:55:24'),
(667, 659, 5, 349, 0, 'BATCH-000659', '2026-06-27', 4339608.00, '2025-07-31 03:55:24'),
(668, 660, 3, 502, 0, 'BATCH-000660', '2027-04-17', 2318800.00, '2025-07-31 03:55:24'),
(669, 661, 2, 360, 0, 'BATCH-000661', '2027-03-08', 752039.00, '2025-07-31 03:55:24'),
(670, 662, 5, 329, 0, 'BATCH-000662', '2028-09-11', 538593.00, '2025-07-31 03:55:24'),
(671, 663, 5, 158, 0, 'BATCH-000663', '2028-08-23', 234206.00, '2025-07-31 03:55:24'),
(672, 664, 4, 53, 0, 'BATCH-000664', '2028-02-08', 3118777.00, '2025-07-31 03:55:24'),
(673, 665, 2, 83, 0, 'BATCH-000665', '2027-11-05', 181908.00, '2025-07-31 03:55:24'),
(674, 666, 2, 118, 0, 'BATCH-000666', '2028-08-18', 1185417.00, '2025-07-31 03:55:24'),
(675, 667, 4, 417, 0, 'BATCH-000667', '2026-07-10', 2775657.00, '2025-07-31 03:55:24'),
(676, 668, 5, 84, 0, 'BATCH-000668', '2027-09-12', 3443547.00, '2025-07-31 03:55:24'),
(677, 669, 1, 495, 0, 'BATCH-000669', '2027-01-05', 220299.00, '2025-07-31 03:55:24'),
(678, 670, 2, 491, 0, 'BATCH-000670', '2028-04-03', 1547358.00, '2025-07-31 03:55:24'),
(679, 671, 3, 328, 0, 'BATCH-000671', '2028-05-12', 2311639.00, '2025-07-31 03:55:24'),
(680, 672, 1, 404, 0, 'BATCH-000672', '2027-03-04', 3968194.00, '2025-07-31 03:55:24'),
(681, 673, 2, 216, 0, 'BATCH-000673', '2026-04-14', 1759948.00, '2025-07-31 03:55:24'),
(682, 674, 6, 254, 0, 'BATCH-000674', '2028-07-10', 1150394.00, '2025-07-31 03:55:24'),
(683, 675, 5, 124, 0, 'BATCH-000675', '2028-10-20', 2441398.00, '2025-07-31 03:55:24'),
(684, 676, 5, 517, 0, 'BATCH-000676', '2027-07-25', 4129609.00, '2025-07-31 03:55:24'),
(685, 677, 7, 539, 0, 'BATCH-000677', '2026-03-26', 1614783.00, '2025-07-31 03:55:24'),
(686, 678, 5, 536, 0, 'BATCH-000678', '2026-03-08', 1284223.00, '2025-07-31 03:55:24'),
(687, 679, 3, 363, 0, 'BATCH-000679', '2026-09-30', 1602977.00, '2025-07-31 03:55:24'),
(688, 680, 1, 97, 0, 'BATCH-000680', '2027-02-07', 2711243.00, '2025-07-31 03:55:24'),
(689, 681, 7, 332, 0, 'BATCH-000681', '2026-08-21', 1527352.00, '2025-07-31 03:55:24'),
(690, 682, 1, 212, 0, 'BATCH-000682', '2027-03-28', 683029.00, '2025-07-31 03:55:24'),
(691, 683, 4, 509, 0, 'BATCH-000683', '2026-07-17', 475343.00, '2025-07-31 03:55:24'),
(692, 684, 1, 402, 0, 'BATCH-000684', '2027-06-28', 2129234.00, '2025-07-31 03:55:24'),
(693, 685, 6, 353, 0, 'BATCH-000685', '2027-10-07', 1236529.00, '2025-07-31 03:55:24'),
(694, 686, 4, 416, 0, 'BATCH-000686', '2026-06-07', 2073636.00, '2025-07-31 03:55:24'),
(695, 687, 7, 114, 0, 'BATCH-000687', '2028-08-28', 1510386.00, '2025-07-31 03:55:24'),
(696, 688, 6, 137, 0, 'BATCH-000688', '2027-02-03', 1509924.00, '2025-07-31 03:55:24'),
(697, 689, 4, 430, 0, 'BATCH-000689', '2026-06-19', 1974573.00, '2025-07-31 03:55:24'),
(698, 690, 6, 281, 0, 'BATCH-000690', '2026-03-18', 3886609.00, '2025-07-31 03:55:24'),
(699, 691, 2, 155, 0, 'BATCH-000691', '2027-08-23', 1078636.00, '2025-07-31 03:55:24'),
(700, 692, 4, 364, 0, 'BATCH-000692', '2028-02-01', 3568858.00, '2025-07-31 03:55:24'),
(701, 693, 6, 241, 0, 'BATCH-000693', '2027-11-16', 660837.00, '2025-07-31 03:55:24'),
(702, 694, 6, 207, 0, 'BATCH-000694', '2026-12-14', 3001455.00, '2025-07-31 03:55:24'),
(703, 695, 3, 455, 0, 'BATCH-000695', '2028-09-22', 1883254.00, '2025-07-31 03:55:24'),
(704, 696, 2, 360, 0, 'BATCH-000696', '2027-09-02', 250438.00, '2025-07-31 03:55:24'),
(705, 697, 4, 266, 0, 'BATCH-000697', '2027-09-23', 3268583.00, '2025-07-31 03:55:24'),
(706, 698, 6, 489, 0, 'BATCH-000698', '2028-09-12', 750549.00, '2025-07-31 03:55:24'),
(707, 699, 7, 165, 0, 'BATCH-000699', '2026-12-13', 4095257.00, '2025-07-31 03:55:24'),
(708, 700, 5, 138, 0, 'BATCH-000700', '2026-06-16', 790585.00, '2025-07-31 03:55:24'),
(709, 701, 4, 409, 0, 'BATCH-000701', '2026-09-30', 366851.00, '2025-07-31 03:55:24'),
(710, 702, 5, 75, 0, 'BATCH-000702', '2026-11-07', 1204699.00, '2025-07-31 03:55:24'),
(711, 703, 4, 343, 0, 'BATCH-000703', '2027-06-14', 3408886.00, '2025-07-31 03:55:24'),
(712, 704, 2, 89, 0, 'BATCH-000704', '2027-09-02', 3079390.00, '2025-07-31 03:55:24'),
(713, 705, 5, 182, 0, 'BATCH-000705', '2026-12-30', 4022970.00, '2025-07-31 03:55:24'),
(714, 706, 4, 333, 0, 'BATCH-000706', '2027-05-31', 3360032.00, '2025-07-31 03:55:24'),
(715, 707, 2, 74, 0, 'BATCH-000707', '2027-05-17', 1042644.00, '2025-07-31 03:55:24'),
(716, 708, 6, 513, 0, 'BATCH-000708', '2027-05-02', 2376192.00, '2025-07-31 03:55:24'),
(717, 709, 2, 382, 0, 'BATCH-000709', '2027-08-25', 3991748.00, '2025-07-31 03:55:24'),
(718, 710, 5, 470, 0, 'BATCH-000710', '2026-05-16', 110084.00, '2025-07-31 03:55:24'),
(719, 711, 6, 478, 0, 'BATCH-000711', '2028-08-12', 339262.00, '2025-07-31 03:55:24'),
(720, 712, 5, 394, 0, 'BATCH-000712', '2027-12-23', 1861988.00, '2025-07-31 03:55:24'),
(721, 713, 7, 367, 0, 'BATCH-000713', '2026-10-05', 1593737.00, '2025-07-31 03:55:24'),
(722, 714, 1, 541, 0, 'BATCH-000714', '2028-07-03', 2242733.00, '2025-07-31 03:55:24'),
(723, 715, 6, 346, 0, 'BATCH-000715', '2027-06-25', 3576655.00, '2025-07-31 03:55:24'),
(724, 716, 3, 416, 0, 'BATCH-000716', '2027-02-27', 3543214.00, '2025-07-31 03:55:24'),
(725, 717, 6, 215, 0, 'BATCH-000717', '2027-04-16', 1025295.00, '2025-07-31 03:55:24'),
(726, 718, 6, 206, 0, 'BATCH-000718', '2026-07-14', 4087918.00, '2025-07-31 03:55:24'),
(727, 719, 1, 256, 0, 'BATCH-000719', '2028-10-04', 3018896.00, '2025-07-31 03:55:24'),
(728, 720, 3, 52, 0, 'BATCH-000720', '2028-04-20', 272031.00, '2025-07-31 03:55:24'),
(729, 721, 6, 88, 0, 'BATCH-000721', '2028-05-07', 4188244.00, '2025-07-31 03:55:24'),
(730, 722, 2, 529, 0, 'BATCH-000722', '2027-01-12', 3945162.00, '2025-07-31 03:55:24'),
(731, 723, 3, 542, 0, 'BATCH-000723', '2028-09-15', 3854874.00, '2025-07-31 03:55:24'),
(732, 724, 3, 235, 0, 'BATCH-000724', '2027-12-20', 1575713.00, '2025-07-31 03:55:24'),
(733, 725, 5, 191, 0, 'BATCH-000725', '2027-03-23', 1136718.00, '2025-07-31 03:55:24'),
(734, 726, 7, 157, 0, 'BATCH-000726', '2026-04-28', 3673440.00, '2025-07-31 03:55:24'),
(735, 727, 6, 323, 0, 'BATCH-000727', '2027-01-04', 327897.00, '2025-07-31 03:55:24'),
(736, 728, 3, 261, 0, 'BATCH-000728', '2026-06-11', 1831963.00, '2025-07-31 03:55:24'),
(737, 729, 5, 495, 0, 'BATCH-000729', '2027-09-06', 1215775.00, '2025-07-31 03:55:24'),
(738, 730, 5, 93, 0, 'BATCH-000730', '2027-12-25', 1033998.00, '2025-07-31 03:55:24'),
(739, 731, 1, 326, 0, 'BATCH-000731', '2027-10-13', 2095383.00, '2025-07-31 03:55:24'),
(740, 732, 4, 466, 0, 'BATCH-000732', '2028-05-02', 2874465.00, '2025-07-31 03:55:24'),
(741, 733, 5, 356, 0, 'BATCH-000733', '2028-09-03', 4127389.00, '2025-07-31 03:55:24'),
(742, 734, 6, 487, 0, 'BATCH-000734', '2026-08-18', 1774743.00, '2025-07-31 03:55:24'),
(743, 735, 3, 340, 0, 'BATCH-000735', '2028-05-28', 2330566.00, '2025-07-31 03:55:24'),
(744, 736, 1, 336, 0, 'BATCH-000736', '2028-03-26', 1041883.00, '2025-07-31 03:55:24'),
(745, 737, 6, 157, 0, 'BATCH-000737', '2028-01-25', 4502084.00, '2025-07-31 03:55:24'),
(746, 738, 6, 74, 0, 'BATCH-000738', '2028-04-23', 4234417.00, '2025-07-31 03:55:24'),
(747, 739, 2, 252, 0, 'BATCH-000739', '2026-11-17', 1148322.00, '2025-07-31 03:55:24'),
(748, 740, 3, 132, 0, 'BATCH-000740', '2027-11-25', 3798694.00, '2025-07-31 03:55:24'),
(749, 741, 2, 312, 0, 'BATCH-000741', '2028-10-20', 1850008.00, '2025-07-31 03:55:24'),
(750, 742, 1, 72, 0, 'BATCH-000742', '2026-03-28', 770699.00, '2025-07-31 03:55:24'),
(751, 743, 5, 457, 0, 'BATCH-000743', '2026-04-22', 4411008.00, '2025-07-31 03:55:24'),
(752, 744, 5, 173, 0, 'BATCH-000744', '2026-12-16', 3961241.00, '2025-07-31 03:55:24'),
(753, 745, 3, 286, 0, 'BATCH-000745', '2026-05-04', 326176.00, '2025-07-31 03:55:24'),
(754, 746, 1, 95, 0, 'BATCH-000746', '2026-10-27', 429832.00, '2025-07-31 03:55:24'),
(755, 747, 5, 530, 0, 'BATCH-000747', '2028-06-07', 1924236.00, '2025-07-31 03:55:24'),
(756, 748, 4, 268, 0, 'BATCH-000748', '2027-08-05', 2108433.00, '2025-07-31 03:55:24'),
(757, 749, 5, 518, 0, 'BATCH-000749', '2027-12-11', 2741586.00, '2025-07-31 03:55:24'),
(758, 750, 7, 103, 0, 'BATCH-000750', '2027-08-24', 2492810.00, '2025-07-31 03:55:24'),
(759, 751, 1, 317, 0, 'BATCH-000751', '2027-08-09', 877410.00, '2025-07-31 03:55:24'),
(760, 752, 3, 478, 0, 'BATCH-000752', '2027-03-25', 2445925.00, '2025-07-31 03:55:24'),
(761, 753, 4, 340, 0, 'BATCH-000753', '2027-09-02', 794215.00, '2025-07-31 03:55:24'),
(762, 754, 1, 92, 0, 'BATCH-000754', '2026-03-27', 207815.00, '2025-07-31 03:55:24'),
(763, 755, 1, 88, 0, 'BATCH-000755', '2026-10-16', 361203.00, '2025-07-31 03:55:24'),
(764, 756, 5, 445, 0, 'BATCH-000756', '2026-06-15', 1471549.00, '2025-07-31 03:55:24'),
(765, 757, 2, 79, 0, 'BATCH-000757', '2027-12-02', 895766.00, '2025-07-31 03:55:24'),
(766, 758, 7, 157, 0, 'BATCH-000758', '2026-08-09', 1464402.00, '2025-07-31 03:55:24'),
(767, 759, 1, 153, 0, 'BATCH-000759', '2028-08-14', 144736.00, '2025-07-31 03:55:24'),
(768, 760, 3, 404, 0, 'BATCH-000760', '2027-05-09', 939783.00, '2025-07-31 03:55:24'),
(769, 761, 5, 324, 0, 'BATCH-000761', '2028-05-17', 2534088.00, '2025-07-31 03:55:24'),
(770, 762, 2, 413, 0, 'BATCH-000762', '2028-03-27', 3481850.00, '2025-07-31 03:55:24'),
(771, 763, 4, 109, 0, 'BATCH-000763', '2026-06-10', 1425543.00, '2025-07-31 03:55:24'),
(772, 764, 2, 506, 0, 'BATCH-000764', '2026-03-19', 2343380.00, '2025-07-31 03:55:24'),
(773, 765, 4, 370, 0, 'BATCH-000765', '2028-06-27', 2222570.00, '2025-07-31 03:55:24'),
(774, 766, 6, 344, 0, 'BATCH-000766', '2027-06-16', 3439716.00, '2025-07-31 03:55:24'),
(775, 767, 3, 144, 0, 'BATCH-000767', '2026-03-23', 3206346.00, '2025-07-31 03:55:24'),
(776, 768, 3, 455, 0, 'BATCH-000768', '2028-07-04', 71711.00, '2025-07-31 03:55:24'),
(777, 769, 3, 534, 0, 'BATCH-000769', '2027-10-27', 1294933.00, '2025-07-31 03:55:24'),
(778, 770, 4, 405, 0, 'BATCH-000770', '2026-02-12', 4265450.00, '2025-07-31 03:55:24'),
(779, 771, 5, 335, 0, 'BATCH-000771', '2028-04-18', 1571981.00, '2025-07-31 03:55:24'),
(780, 772, 3, 279, 0, 'BATCH-000772', '2027-02-21', 2600059.00, '2025-07-31 03:55:24'),
(781, 773, 5, 460, 0, 'BATCH-000773', '2028-09-29', 1901967.00, '2025-07-31 03:55:24'),
(782, 774, 2, 352, 0, 'BATCH-000774', '2027-06-15', 3182068.00, '2025-07-31 03:55:24'),
(783, 775, 1, 528, 0, 'BATCH-000775', '2028-02-09', 3802100.00, '2025-07-31 03:55:24'),
(784, 776, 7, 251, 0, 'BATCH-000776', '2026-03-21', 284890.00, '2025-07-31 03:55:24'),
(785, 777, 2, 322, 0, 'BATCH-000777', '2026-11-12', 3659185.00, '2025-07-31 03:55:24'),
(786, 778, 2, 303, 0, 'BATCH-000778', '2028-09-20', 1436372.00, '2025-07-31 03:55:24'),
(787, 779, 5, 287, 0, 'BATCH-000779', '2026-12-07', 693765.00, '2025-07-31 03:55:24'),
(788, 780, 6, 363, 0, 'BATCH-000780', '2027-12-16', 2527391.00, '2025-07-31 03:55:24'),
(789, 781, 6, 542, 0, 'BATCH-000781', '2028-01-26', 3112286.00, '2025-07-31 03:55:24'),
(790, 782, 2, 167, 0, 'BATCH-000782', '2027-02-25', 1207338.00, '2025-07-31 03:55:24'),
(791, 783, 2, 522, 0, 'BATCH-000783', '2026-10-28', 2433774.00, '2025-07-31 03:55:24'),
(792, 784, 7, 422, 0, 'BATCH-000784', '2026-05-16', 1402170.00, '2025-07-31 03:55:24'),
(793, 785, 2, 139, 0, 'BATCH-000785', '2026-09-11', 2720777.00, '2025-07-31 03:55:24'),
(794, 786, 3, 473, 0, 'BATCH-000786', '2026-09-28', 3062625.00, '2025-07-31 03:55:24'),
(795, 787, 5, 184, 0, 'BATCH-000787', '2027-01-23', 9454.00, '2025-07-31 03:55:24'),
(796, 788, 7, 342, 0, 'BATCH-000788', '2026-07-23', 582297.00, '2025-07-31 03:55:24'),
(797, 789, 1, 126, 0, 'BATCH-000789', '2027-04-13', 3374108.00, '2025-07-31 03:55:24'),
(798, 790, 3, 470, 0, 'BATCH-000790', '2028-09-04', 1064868.00, '2025-07-31 03:55:24'),
(799, 791, 3, 499, 0, 'BATCH-000791', '2027-07-13', 4358933.00, '2025-07-31 03:55:24'),
(800, 792, 2, 189, 0, 'BATCH-000792', '2027-12-18', 2771686.00, '2025-07-31 03:55:24'),
(801, 793, 7, 125, 0, 'BATCH-000793', '2028-02-23', 1526832.00, '2025-07-31 03:55:24'),
(802, 794, 3, 77, 0, 'BATCH-000794', '2026-03-05', 108771.00, '2025-07-31 03:55:24'),
(803, 795, 7, 511, 0, 'BATCH-000795', '2027-10-11', 1547024.00, '2025-07-31 03:55:24'),
(804, 796, 6, 144, 0, 'BATCH-000796', '2027-03-14', 2230901.00, '2025-07-31 03:55:24'),
(805, 797, 2, 396, 0, 'BATCH-000797', '2028-02-28', 3302114.00, '2025-07-31 03:55:24'),
(806, 798, 3, 383, 0, 'BATCH-000798', '2026-08-29', 334190.00, '2025-07-31 03:55:24'),
(807, 799, 6, 240, 0, 'BATCH-000799', '2028-02-07', 2568072.00, '2025-07-31 03:55:24'),
(808, 800, 5, 244, 0, 'BATCH-000800', '2026-04-22', 1191155.00, '2025-07-31 03:55:24'),
(809, 801, 1, 299, 0, 'BATCH-000801', '2026-12-12', 464446.00, '2025-07-31 03:55:24'),
(810, 802, 4, 271, 0, 'BATCH-000802', '2027-08-14', 2233365.00, '2025-07-31 03:55:24'),
(811, 803, 6, 256, 0, 'BATCH-000803', '2028-01-26', 1836288.00, '2025-07-31 03:55:24'),
(812, 804, 6, 548, 0, 'BATCH-000804', '2027-04-30', 1356270.00, '2025-07-31 03:55:24'),
(813, 805, 1, 406, 0, 'BATCH-000805', '2026-08-14', 3873271.00, '2025-07-31 03:55:24'),
(814, 806, 5, 499, 0, 'BATCH-000806', '2027-03-12', 1586217.00, '2025-07-31 03:55:24'),
(815, 807, 4, 336, 0, 'BATCH-000807', '2026-11-10', 3249539.00, '2025-07-31 03:55:24'),
(816, 808, 6, 317, 0, 'BATCH-000808', '2027-04-26', 3020396.00, '2025-07-31 03:55:24'),
(817, 809, 7, 504, 0, 'BATCH-000809', '2027-09-17', 1195080.00, '2025-07-31 03:55:24'),
(818, 810, 4, 461, 0, 'BATCH-000810', '2027-07-26', 1172281.00, '2025-07-31 03:55:24'),
(819, 811, 5, 305, 0, 'BATCH-000811', '2027-08-31', 1702988.00, '2025-07-31 03:55:24'),
(820, 812, 1, 329, 0, 'BATCH-000812', '2027-02-14', 1082322.00, '2025-07-31 03:55:24'),
(821, 813, 1, 300, 0, 'BATCH-000813', '2027-02-07', 1706494.00, '2025-07-31 03:55:24'),
(822, 814, 6, 379, 0, 'BATCH-000814', '2026-02-16', 571330.00, '2025-07-31 03:55:24'),
(823, 815, 4, 273, 0, 'BATCH-000815', '2027-07-22', 1652113.00, '2025-07-31 03:55:24'),
(824, 816, 2, 509, 0, 'BATCH-000816', '2028-10-10', 809184.00, '2025-07-31 03:55:24'),
(825, 817, 7, 104, 0, 'BATCH-000817', '2028-02-26', 2141064.00, '2025-07-31 03:55:24'),
(826, 818, 1, 61, 0, 'BATCH-000818', '2028-05-22', 753140.00, '2025-07-31 03:55:24'),
(827, 819, 3, 520, 0, 'BATCH-000819', '2028-05-21', 1812875.00, '2025-07-31 03:55:24'),
(828, 820, 4, 122, 0, 'BATCH-000820', '2026-12-12', 723777.00, '2025-07-31 03:55:24'),
(829, 821, 6, 405, 0, 'BATCH-000821', '2026-03-08', 324535.00, '2025-07-31 03:55:24'),
(830, 822, 2, 520, 0, 'BATCH-000822', '2026-02-09', 1101755.00, '2025-07-31 03:55:24'),
(831, 823, 2, 125, 0, 'BATCH-000823', '2026-09-08', 3026711.00, '2025-07-31 03:55:24'),
(832, 824, 5, 245, 0, 'BATCH-000824', '2028-07-31', 1831858.00, '2025-07-31 03:55:24'),
(833, 825, 2, 137, 0, 'BATCH-000825', '2026-03-09', 3075839.00, '2025-07-31 03:55:24'),
(834, 826, 2, 237, 0, 'BATCH-000826', '2026-02-23', 44192.00, '2025-07-31 03:55:24'),
(835, 827, 7, 434, 0, 'BATCH-000827', '2028-09-21', 2426786.00, '2025-07-31 03:55:24'),
(836, 828, 6, 196, 0, 'BATCH-000828', '2026-05-25', 3220164.00, '2025-07-31 03:55:24'),
(837, 829, 2, 516, 0, 'BATCH-000829', '2026-02-15', 1358608.00, '2025-07-31 03:55:24'),
(838, 830, 4, 203, 0, 'BATCH-000830', '2026-08-24', 581129.00, '2025-07-31 03:55:24'),
(839, 831, 1, 379, 0, 'BATCH-000831', '2026-10-24', 1691907.00, '2025-07-31 03:55:24'),
(840, 832, 1, 139, 0, 'BATCH-000832', '2028-01-11', 164611.00, '2025-07-31 03:55:24'),
(841, 833, 1, 74, 0, 'BATCH-000833', '2026-07-01', 2829093.00, '2025-07-31 03:55:24'),
(842, 834, 5, 282, 0, 'BATCH-000834', '2026-12-14', 957581.00, '2025-07-31 03:55:24'),
(843, 835, 1, 457, 0, 'BATCH-000835', '2028-04-15', 2705893.00, '2025-07-31 03:55:24'),
(844, 836, 4, 74, 0, 'BATCH-000836', '2027-07-20', 2469259.00, '2025-07-31 03:55:24'),
(845, 837, 1, 522, 0, 'BATCH-000837', '2027-02-06', 190678.00, '2025-07-31 03:55:24'),
(846, 838, 1, 181, 0, 'BATCH-000838', '2026-04-18', 2804526.00, '2025-07-31 03:55:24'),
(847, 839, 7, 272, 0, 'BATCH-000839', '2027-10-30', 3919691.00, '2025-07-31 03:55:24'),
(848, 840, 3, 303, 0, 'BATCH-000840', '2026-10-22', 3699477.00, '2025-07-31 03:55:24'),
(849, 841, 3, 59, 0, 'BATCH-000841', '2026-08-18', 4337692.00, '2025-07-31 03:55:24'),
(850, 842, 2, 108, 0, 'BATCH-000842', '2028-10-07', 2582756.00, '2025-07-31 03:55:24'),
(851, 843, 7, 457, 0, 'BATCH-000843', '2027-01-14', 1444176.00, '2025-07-31 03:55:24'),
(852, 844, 4, 418, 0, 'BATCH-000844', '2026-04-03', 561219.00, '2025-07-31 03:55:24'),
(853, 845, 3, 403, 0, 'BATCH-000845', '2026-11-10', 1431850.00, '2025-07-31 03:55:24'),
(854, 846, 6, 376, 0, 'BATCH-000846', '2026-05-13', 2577773.00, '2025-07-31 03:55:24'),
(855, 847, 4, 533, 0, 'BATCH-000847', '2026-09-13', 1108412.00, '2025-07-31 03:55:24'),
(856, 848, 4, 518, 0, 'BATCH-000848', '2026-04-23', 2797740.00, '2025-07-31 03:55:24'),
(857, 849, 6, 218, 0, 'BATCH-000849', '2026-07-15', 3755434.00, '2025-07-31 03:55:24'),
(858, 850, 5, 442, 0, 'BATCH-000850', '2028-09-08', 1909104.00, '2025-07-31 03:55:24'),
(859, 851, 2, 530, 0, 'BATCH-000851', '2026-04-03', 2044507.00, '2025-07-31 03:55:24'),
(860, 852, 1, 525, 0, 'BATCH-000852', '2027-08-22', 40673.00, '2025-07-31 03:55:24'),
(861, 853, 3, 336, 0, 'BATCH-000853', '2028-07-25', 3757618.00, '2025-07-31 03:55:24'),
(862, 854, 4, 384, 0, 'BATCH-000854', '2026-03-12', 980610.00, '2025-07-31 03:55:24'),
(863, 855, 7, 91, 0, 'BATCH-000855', '2027-08-28', 2894116.00, '2025-07-31 03:55:24'),
(864, 856, 4, 267, 0, 'BATCH-000856', '2028-02-22', 2164459.00, '2025-07-31 03:55:24'),
(865, 857, 1, 148, 0, 'BATCH-000857', '2027-09-20', 1897946.00, '2025-07-31 03:55:24'),
(866, 858, 3, 155, 0, 'BATCH-000858', '2026-07-20', 1086473.00, '2025-07-31 03:55:24'),
(867, 859, 5, 374, 0, 'BATCH-000859', '2026-09-10', 838497.00, '2025-07-31 03:55:24'),
(868, 860, 2, 380, 0, 'BATCH-000860', '2027-08-24', 4012180.00, '2025-07-31 03:55:24'),
(869, 861, 6, 530, 0, 'BATCH-000861', '2027-10-17', 1171421.00, '2025-07-31 03:55:24'),
(870, 862, 3, 179, 0, 'BATCH-000862', '2026-04-13', 2722725.00, '2025-07-31 03:55:24'),
(871, 863, 6, 113, 0, 'BATCH-000863', '2026-10-26', 4421531.00, '2025-07-31 03:55:24'),
(872, 864, 1, 296, 0, 'BATCH-000864', '2026-08-19', 2456317.00, '2025-07-31 03:55:24'),
(873, 865, 1, 499, 0, 'BATCH-000865', '2026-07-19', 784665.00, '2025-07-31 03:55:24'),
(874, 866, 3, 146, 0, 'BATCH-000866', '2028-08-26', 590488.00, '2025-07-31 03:55:24'),
(875, 867, 6, 407, 0, 'BATCH-000867', '2026-05-19', 1891591.00, '2025-07-31 03:55:24'),
(876, 868, 6, 309, 0, 'BATCH-000868', '2026-12-21', 398187.00, '2025-07-31 03:55:24'),
(877, 869, 4, 539, 0, 'BATCH-000869', '2027-08-05', 3771307.00, '2025-07-31 03:55:24'),
(878, 870, 4, 85, 0, 'BATCH-000870', '2028-04-13', 3717168.00, '2025-07-31 03:55:24'),
(879, 871, 5, 60, 0, 'BATCH-000871', '2026-02-04', 4424723.00, '2025-07-31 03:55:24'),
(880, 872, 7, 279, 0, 'BATCH-000872', '2027-11-10', 4001348.00, '2025-07-31 03:55:24'),
(881, 873, 4, 414, 0, 'BATCH-000873', '2026-08-29', 3971717.00, '2025-07-31 03:55:24'),
(882, 874, 6, 133, 0, 'BATCH-000874', '2027-07-29', 1101779.00, '2025-07-31 03:55:24'),
(883, 875, 4, 108, 0, 'BATCH-000875', '2028-06-19', 113272.00, '2025-07-31 03:55:24'),
(884, 876, 4, 248, 0, 'BATCH-000876', '2027-06-16', 1520118.00, '2025-07-31 03:55:24'),
(885, 877, 2, 454, 0, 'BATCH-000877', '2027-08-08', 1637378.00, '2025-07-31 03:55:24'),
(886, 878, 1, 345, 0, 'BATCH-000878', '2027-07-31', 4403156.00, '2025-07-31 03:55:24'),
(887, 879, 2, 167, 0, 'BATCH-000879', '2027-05-19', 3066961.00, '2025-07-31 03:55:24'),
(888, 880, 7, 449, 0, 'BATCH-000880', '2026-04-25', 224165.00, '2025-07-31 03:55:24'),
(889, 881, 7, 414, 0, 'BATCH-000881', '2028-01-17', 1876792.00, '2025-07-31 03:55:24'),
(890, 882, 7, 215, 0, 'BATCH-000882', '2028-07-24', 2494309.00, '2025-07-31 03:55:24'),
(891, 883, 1, 309, 0, 'BATCH-000883', '2027-05-27', 3939728.00, '2025-07-31 03:55:24'),
(892, 884, 7, 518, 0, 'BATCH-000884', '2028-09-01', 4199738.00, '2025-07-31 03:55:24'),
(893, 885, 6, 184, 0, 'BATCH-000885', '2028-07-23', 3304151.00, '2025-07-31 03:55:24'),
(894, 886, 7, 296, 0, 'BATCH-000886', '2027-11-11', 3557053.00, '2025-07-31 03:55:24'),
(895, 887, 7, 320, 0, 'BATCH-000887', '2028-02-27', 845155.00, '2025-07-31 03:55:24'),
(896, 888, 5, 381, 0, 'BATCH-000888', '2027-02-14', 4178903.00, '2025-07-31 03:55:24'),
(897, 889, 4, 370, 0, 'BATCH-000889', '2028-02-20', 3818363.00, '2025-07-31 03:55:24'),
(898, 890, 7, 207, 0, 'BATCH-000890', '2027-11-18', 1619206.00, '2025-07-31 03:55:24'),
(899, 891, 6, 535, 0, 'BATCH-000891', '2027-03-30', 1012177.00, '2025-07-31 03:55:24'),
(900, 892, 6, 301, 0, 'BATCH-000892', '2026-02-05', 2433232.00, '2025-07-31 03:55:24'),
(901, 893, 5, 408, 0, 'BATCH-000893', '2027-09-05', 3524204.00, '2025-07-31 03:55:24'),
(902, 894, 2, 244, 0, 'BATCH-000894', '2027-06-16', 1622205.00, '2025-07-31 03:55:24'),
(903, 895, 2, 207, 0, 'BATCH-000895', '2028-02-04', 3367915.00, '2025-07-31 03:55:24'),
(904, 896, 4, 228, 0, 'BATCH-000896', '2026-09-06', 208126.00, '2025-07-31 03:55:24'),
(905, 897, 4, 370, 0, 'BATCH-000897', '2027-07-20', 3498056.00, '2025-07-31 03:55:24'),
(906, 898, 2, 534, 0, 'BATCH-000898', '2026-04-01', 1886935.00, '2025-07-31 03:55:24'),
(907, 899, 7, 159, 0, 'BATCH-000899', '2027-03-13', 1788398.00, '2025-07-31 03:55:24'),
(908, 900, 6, 324, 0, 'BATCH-000900', '2027-06-17', 3990915.00, '2025-07-31 03:55:24'),
(909, 901, 7, 484, 0, 'BATCH-000901', '2027-10-18', 2435589.00, '2025-07-31 03:55:24'),
(910, 902, 6, 265, 0, 'BATCH-000902', '2028-01-24', 1554809.00, '2025-07-31 03:55:24'),
(911, 903, 4, 373, 0, 'BATCH-000903', '2027-10-18', 928820.00, '2025-07-31 03:55:24'),
(912, 904, 1, 81, 0, 'BATCH-000904', '2028-07-21', 1557854.00, '2025-07-31 03:55:24'),
(913, 905, 1, 541, 0, 'BATCH-000905', '2028-07-15', 2521537.00, '2025-07-31 03:55:24'),
(914, 906, 1, 437, 0, 'BATCH-000906', '2027-09-21', 3112960.00, '2025-07-31 03:55:24'),
(915, 907, 5, 119, 0, 'BATCH-000907', '2028-03-04', 1912769.00, '2025-07-31 03:55:24'),
(916, 908, 6, 447, 0, 'BATCH-000908', '2027-07-17', 1342058.00, '2025-07-31 03:55:24'),
(917, 909, 7, 288, 0, 'BATCH-000909', '2028-03-03', 1803641.00, '2025-07-31 03:55:24'),
(918, 910, 5, 193, 0, 'BATCH-000910', '2027-01-04', 3854125.00, '2025-07-31 03:55:24'),
(919, 911, 2, 379, 0, 'BATCH-000911', '2027-08-13', 3781898.00, '2025-07-31 03:55:24'),
(920, 912, 4, 549, 0, 'BATCH-000912', '2027-05-26', 1918836.00, '2025-07-31 03:55:24'),
(921, 913, 5, 90, 0, 'BATCH-000913', '2027-02-23', 3238940.00, '2025-07-31 03:55:24'),
(922, 914, 3, 506, 0, 'BATCH-000914', '2026-12-15', 3942715.00, '2025-07-31 03:55:24'),
(923, 915, 3, 250, 0, 'BATCH-000915', '2028-03-28', 3409176.00, '2025-07-31 03:55:24'),
(924, 916, 3, 424, 0, 'BATCH-000916', '2027-07-14', 1899372.00, '2025-07-31 03:55:24'),
(925, 917, 4, 174, 0, 'BATCH-000917', '2028-02-03', 4253326.00, '2025-07-31 03:55:24'),
(926, 918, 4, 393, 0, 'BATCH-000918', '2028-08-04', 2453587.00, '2025-07-31 03:55:24'),
(927, 919, 7, 125, 0, 'BATCH-000919', '2028-07-04', 4472998.00, '2025-07-31 03:55:24'),
(928, 920, 3, 293, 0, 'BATCH-000920', '2027-08-04', 1409799.00, '2025-07-31 03:55:24'),
(929, 921, 7, 320, 0, 'BATCH-000921', '2026-02-16', 2160202.00, '2025-07-31 03:55:24'),
(930, 922, 3, 158, 0, 'BATCH-000922', '2026-04-29', 3667753.00, '2025-07-31 03:55:24'),
(931, 923, 6, 300, 0, 'BATCH-000923', '2026-06-20', 974852.00, '2025-07-31 03:55:24'),
(932, 924, 5, 332, 0, 'BATCH-000924', '2028-07-18', 3698440.00, '2025-07-31 03:55:24'),
(933, 925, 3, 293, 0, 'BATCH-000925', '2026-10-24', 4013995.00, '2025-07-31 03:55:24'),
(934, 926, 5, 311, 0, 'BATCH-000926', '2027-12-25', 4138571.00, '2025-07-31 03:55:24'),
(935, 927, 4, 418, 0, 'BATCH-000927', '2026-08-03', 3308279.00, '2025-07-31 03:55:24'),
(936, 928, 1, 202, 0, 'BATCH-000928', '2026-09-08', 927582.00, '2025-07-31 03:55:24'),
(937, 929, 3, 116, 0, 'BATCH-000929', '2027-10-06', 3102161.00, '2025-07-31 03:55:24'),
(938, 930, 5, 483, 0, 'BATCH-000930', '2027-08-28', 1319104.00, '2025-07-31 03:55:24'),
(939, 931, 6, 414, 0, 'BATCH-000931', '2027-05-27', 1089530.00, '2025-07-31 03:55:24'),
(940, 932, 6, 549, 0, 'BATCH-000932', '2028-03-04', 3773506.00, '2025-07-31 03:55:24'),
(941, 933, 7, 499, 0, 'BATCH-000933', '2028-05-24', 2472595.00, '2025-07-31 03:55:24'),
(942, 934, 2, 208, 0, 'BATCH-000934', '2026-02-01', 358140.00, '2025-07-31 03:55:24'),
(943, 935, 3, 366, 0, 'BATCH-000935', '2026-03-12', 1473959.00, '2025-07-31 03:55:24'),
(944, 936, 4, 296, 0, 'BATCH-000936', '2028-10-06', 1970541.00, '2025-07-31 03:55:24'),
(945, 937, 2, 474, 0, 'BATCH-000937', '2027-07-30', 917069.00, '2025-07-31 03:55:24'),
(946, 938, 3, 149, 0, 'BATCH-000938', '2028-07-27', 4352998.00, '2025-07-31 03:55:24'),
(947, 939, 1, 326, 0, 'BATCH-000939', '2027-06-07', 3707839.00, '2025-07-31 03:55:24'),
(948, 940, 5, 371, 0, 'BATCH-000940', '2027-01-07', 3608116.00, '2025-07-31 03:55:24'),
(949, 941, 7, 260, 0, 'BATCH-000941', '2026-08-30', 3660663.00, '2025-07-31 03:55:24'),
(950, 942, 3, 363, 0, 'BATCH-000942', '2028-07-13', 2762111.00, '2025-07-31 03:55:24'),
(951, 943, 3, 541, 0, 'BATCH-000943', '2028-05-01', 802396.00, '2025-07-31 03:55:24'),
(952, 944, 3, 301, 0, 'BATCH-000944', '2026-11-20', 4402803.00, '2025-07-31 03:55:24'),
(953, 945, 7, 62, 0, 'BATCH-000945', '2026-06-27', 3079321.00, '2025-07-31 03:55:24'),
(954, 946, 7, 422, 0, 'BATCH-000946', '2028-05-21', 4492123.00, '2025-07-31 03:55:24'),
(955, 947, 4, 167, 0, 'BATCH-000947', '2028-05-18', 2285116.00, '2025-07-31 03:55:24'),
(956, 948, 1, 297, 0, 'BATCH-000948', '2027-05-09', 3844830.00, '2025-07-31 03:55:24'),
(957, 949, 7, 422, 0, 'BATCH-000949', '2026-06-15', 2094367.00, '2025-07-31 03:55:24'),
(958, 950, 7, 106, 0, 'BATCH-000950', '2028-06-05', 4348715.00, '2025-07-31 03:55:24'),
(959, 951, 2, 207, 0, 'BATCH-000951', '2028-05-25', 1377446.00, '2025-07-31 03:55:24'),
(960, 952, 7, 523, 0, 'BATCH-000952', '2028-04-23', 1130190.00, '2025-07-31 03:55:24'),
(961, 953, 6, 158, 0, 'BATCH-000953', '2028-01-04', 3994049.00, '2025-07-31 03:55:24'),
(962, 954, 3, 486, 0, 'BATCH-000954', '2027-04-21', 2825434.00, '2025-07-31 03:55:24'),
(963, 955, 6, 66, 0, 'BATCH-000955', '2028-04-26', 17962.00, '2025-07-31 03:55:24'),
(964, 956, 4, 420, 0, 'BATCH-000956', '2026-03-21', 212938.00, '2025-07-31 03:55:24'),
(965, 957, 1, 151, 0, 'BATCH-000957', '2028-04-15', 1994873.00, '2025-07-31 03:55:24'),
(966, 958, 6, 332, 0, 'BATCH-000958', '2027-05-31', 3405638.00, '2025-07-31 03:55:24'),
(967, 959, 3, 181, 0, 'BATCH-000959', '2027-03-03', 961254.00, '2025-07-31 03:55:24'),
(968, 960, 7, 376, 0, 'BATCH-000960', '2027-12-20', 2265479.00, '2025-07-31 03:55:24'),
(969, 961, 4, 377, 0, 'BATCH-000961', '2028-09-27', 4109734.00, '2025-07-31 03:55:24'),
(970, 962, 5, 266, 0, 'BATCH-000962', '2026-10-15', 47041.00, '2025-07-31 03:55:24'),
(971, 963, 2, 187, 0, 'BATCH-000963', '2027-09-12', 658569.00, '2025-07-31 03:55:24'),
(972, 964, 7, 186, 0, 'BATCH-000964', '2027-07-21', 3991061.00, '2025-07-31 03:55:24'),
(973, 965, 6, 230, 0, 'BATCH-000965', '2027-02-24', 4001696.00, '2025-07-31 03:55:24'),
(974, 966, 2, 357, 0, 'BATCH-000966', '2026-12-05', 3217957.00, '2025-07-31 03:55:24'),
(975, 967, 5, 55, 0, 'BATCH-000967', '2026-07-09', 3533925.00, '2025-07-31 03:55:24'),
(976, 968, 3, 445, 0, 'BATCH-000968', '2027-11-27', 4393797.00, '2025-07-31 03:55:24'),
(977, 969, 7, 250, 0, 'BATCH-000969', '2027-03-08', 3736373.00, '2025-07-31 03:55:24'),
(978, 970, 7, 120, 0, 'BATCH-000970', '2028-08-17', 1090539.00, '2025-07-31 03:55:24'),
(979, 971, 3, 196, 0, 'BATCH-000971', '2026-10-10', 1820688.00, '2025-07-31 03:55:24'),
(980, 972, 2, 58, 0, 'BATCH-000972', '2027-01-07', 3074431.00, '2025-07-31 03:55:24'),
(981, 973, 3, 450, 0, 'BATCH-000973', '2028-07-16', 465967.00, '2025-07-31 03:55:24'),
(982, 974, 6, 408, 0, 'BATCH-000974', '2026-07-18', 3209979.00, '2025-07-31 03:55:24'),
(983, 975, 1, 82, 0, 'BATCH-000975', '2026-08-17', 3691433.00, '2025-07-31 03:55:24'),
(984, 976, 4, 536, 0, 'BATCH-000976', '2027-03-11', 565242.00, '2025-07-31 03:55:24'),
(985, 977, 3, 347, 0, 'BATCH-000977', '2028-03-27', 783941.00, '2025-07-31 03:55:24'),
(986, 978, 4, 514, 0, 'BATCH-000978', '2026-07-26', 519336.00, '2025-07-31 03:55:24'),
(987, 979, 1, 445, 0, 'BATCH-000979', '2028-06-21', 44863.00, '2025-07-31 03:55:24'),
(988, 980, 3, 67, 0, 'BATCH-000980', '2028-08-26', 2733769.00, '2025-07-31 03:55:24'),
(989, 981, 2, 143, 0, 'BATCH-000981', '2026-12-25', 461051.00, '2025-07-31 03:55:24'),
(990, 982, 4, 165, 0, 'BATCH-000982', '2027-10-20', 2117070.00, '2025-07-31 03:55:24'),
(991, 983, 4, 466, 0, 'BATCH-000983', '2028-04-26', 2722056.00, '2025-07-31 03:55:24'),
(992, 984, 4, 532, 0, 'BATCH-000984', '2026-07-06', 4094672.00, '2025-07-31 03:55:24'),
(993, 985, 1, 334, 0, 'BATCH-000985', '2027-11-27', 2898003.00, '2025-07-31 03:55:24'),
(994, 986, 2, 89, 0, 'BATCH-000986', '2028-03-28', 3258707.00, '2025-07-31 03:55:24'),
(995, 987, 2, 56, 0, 'BATCH-000987', '2027-01-21', 3410340.00, '2025-07-31 03:55:24'),
(996, 988, 5, 171, 0, 'BATCH-000988', '2026-05-17', 3703479.00, '2025-07-31 03:55:24'),
(997, 989, 6, 255, 0, 'BATCH-000989', '2028-01-31', 1967922.00, '2025-07-31 03:55:24'),
(998, 990, 7, 333, 0, 'BATCH-000990', '2028-07-29', 3927325.00, '2025-07-31 03:55:24'),
(999, 991, 5, 268, 0, 'BATCH-000991', '2027-01-16', 2082878.00, '2025-07-31 03:55:24'),
(1000, 992, 2, 464, 0, 'BATCH-000992', '2027-03-21', 2725752.00, '2025-07-31 03:55:24'),
(1001, 993, 6, 56, 0, 'BATCH-000993', '2028-03-05', 3631733.00, '2025-07-31 03:55:24'),
(1002, 994, 6, 143, 0, 'BATCH-000994', '2028-03-06', 1310644.00, '2025-07-31 03:55:24'),
(1003, 995, 1, 462, 0, 'BATCH-000995', '2028-01-04', 292597.00, '2025-07-31 03:55:24'),
(1004, 996, 2, 439, 0, 'BATCH-000996', '2026-12-09', 1110511.00, '2025-07-31 03:55:24'),
(1005, 997, 2, 368, 0, 'BATCH-000997', '2027-01-27', 4117100.00, '2025-07-31 03:55:24'),
(1006, 998, 4, 354, 0, 'BATCH-000998', '2027-10-26', 1626013.00, '2025-07-31 03:55:24'),
(1007, 999, 7, 223, 0, 'BATCH-000999', '2026-04-18', 1649387.00, '2025-07-31 03:55:24'),
(1008, 1000, 5, 451, 0, 'BATCH-001000', '2026-11-02', 4444815.00, '2025-07-31 03:55:24'),
(1009, 1001, 1, 300, 0, 'BATCH-001001', '2026-09-12', 2883241.00, '2025-07-31 03:55:24'),
(1010, 1002, 4, 366, 0, 'BATCH-001002', '2027-10-28', 1333634.00, '2025-07-31 03:55:24'),
(1011, 1003, 4, 495, 0, 'BATCH-001003', '2028-03-29', 1305977.00, '2025-07-31 03:55:24'),
(1012, 1004, 1, 278, 0, 'BATCH-001004', '2026-04-25', 337958.00, '2025-07-31 03:55:24'),
(1013, 1005, 1, 193, 0, 'BATCH-001005', '2026-06-05', 3547603.00, '2025-07-31 03:55:24'),
(1014, 1006, 4, 232, 0, 'BATCH-001006', '2026-08-05', 3865397.00, '2025-07-31 03:55:24'),
(1015, 1007, 6, 50, 0, 'BATCH-001007', '2028-06-06', 1387475.00, '2025-07-31 03:55:24'),
(1016, 1008, 7, 457, 0, 'BATCH-001008', '2026-09-15', 3218677.00, '2025-07-31 03:55:24'),
(1017, 1009, 7, 163, 0, 'BATCH-001009', '2027-06-26', 4032783.00, '2025-07-31 03:55:24'),
(1018, 1010, 7, 524, 0, 'BATCH-001010', '2028-09-19', 4443898.00, '2025-07-31 03:55:24'),
(1019, 1011, 1, 143, 0, 'BATCH-001011', '2028-05-21', 3013699.00, '2025-07-31 03:55:24'),
(1020, 1012, 6, 57, 0, 'BATCH-001012', '2027-11-17', 1155010.00, '2025-07-31 03:55:24'),
(1021, 1013, 3, 408, 0, 'BATCH-001013', '2027-12-23', 1470974.00, '2025-07-31 03:55:24'),
(1022, 1014, 4, 412, 0, 'BATCH-001014', '2026-02-04', 3900181.00, '2025-07-31 03:55:24'),
(1023, 1015, 3, 500, 0, 'BATCH-001015', '2027-09-27', 1525315.00, '2025-07-31 03:55:24'),
(1024, 1016, 7, 198, 0, 'BATCH-001016', '2028-07-11', 2680430.00, '2025-07-31 03:55:24'),
(1025, 1017, 2, 358, 0, 'BATCH-001017', '2026-10-01', 1749109.00, '2025-07-31 03:55:24'),
(1026, 1018, 2, 447, 0, 'BATCH-001018', '2027-03-01', 2741598.00, '2025-07-31 03:55:24'),
(1027, 1019, 6, 247, 0, 'BATCH-001019', '2027-04-12', 102421.00, '2025-07-31 03:55:24'),
(1028, 1020, 6, 475, 0, 'BATCH-001020', '2028-07-24', 4472851.00, '2025-07-31 03:55:24'),
(1029, 1021, 2, 143, 0, 'BATCH-001021', '2026-09-20', 2803738.00, '2025-07-31 03:55:24');

-- --------------------------------------------------------

--
-- Table structure for table `stock_movements`
--

CREATE TABLE `stock_movements` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `location_id` int(11) NOT NULL,
  `movement_type` enum('in','out','transfer','adjustment') NOT NULL,
  `reference_type` enum('purchase','sale','transfer','adjustment','return') NOT NULL,
  `reference_id` int(11) DEFAULT NULL,
  `quantity` int(11) NOT NULL,
  `unit_cost` decimal(10,2) DEFAULT 0.00,
  `batch_number` varchar(100) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `movement_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `created_by` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `stock_movements`
--

INSERT INTO `stock_movements` (`id`, `product_id`, `location_id`, `movement_type`, `reference_type`, `reference_id`, `quantity`, `unit_cost`, `batch_number`, `notes`, `movement_date`, `created_by`) VALUES
(1, 1, 1, 'out', 'transfer', NULL, 5, 4200000.00, 'BATCH001', 'Transfer to location 2', '2025-07-30 23:52:08', 'admin'),
(2, 1, 2, 'in', 'transfer', NULL, 5, 4200000.00, 'BATCH001', 'Transfer from location 1', '2025-07-30 23:52:08', 'admin'),
(3, 1, 1, 'out', 'transfer', NULL, 5, 4200000.00, 'BATCH001', 'Transfer to location 2', '2025-07-31 05:11:01', 'admin'),
(4, 1, 2, 'in', 'transfer', NULL, 5, 4200000.00, 'BATCH001', 'Transfer from location 1', '2025-07-31 05:11:01', 'admin');

-- --------------------------------------------------------

--
-- Table structure for table `suppliers`
--

CREATE TABLE `suppliers` (
  `id` int(11) NOT NULL,
  `name` varchar(150) NOT NULL,
  `contact_person` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `city` varchar(50) DEFAULT NULL,
  `postal_code` varchar(10) DEFAULT NULL,
  `status` enum('active','inactive') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `suppliers`
--

INSERT INTO `suppliers` (`id`, `name`, `contact_person`, `phone`, `email`, `address`, `city`, `postal_code`, `status`, `created_at`, `updated_at`) VALUES
(1, 'PT Elektronik Jaya', 'Budi Santoso', '081234567890', 'budi@elektronikjaya.com', 'Jl. Sudirman No. 123', 'Jakarta', '10220', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(2, 'CV Fashion Store', 'Siti Nurhaliza', '082345678901', 'siti@fashionstore.com', 'Jl. Malioboro No. 45', 'Yogyakarta', '55271', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(3, 'UD Sumber Rejeki', 'Ahmad Rahman', '083456789012', 'ahmad@sumberrejeki.com', 'Jl. Pasar Baru No. 67', 'Bandung', '40181', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(4, 'PT Office Solutions', 'Maria Gonzales', '084567890123', 'maria@officesolutions.com', 'Jl. Thamrin No. 89', 'Jakarta', '10230', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(5, 'CV Home Living', 'Indra Kusuma', '085678901234', 'indra@homeliving.com', 'Jl. Pemuda No. 56', 'Semarang', '50132', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(6, 'PT Sports Central', 'Ravi Kumar', '086789012345', 'ravi@sportscentral.com', 'Jl. Veteran No. 78', 'Surabaya', '60119', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(7, 'Auto Parts Indonesia', 'Kevin Tan', '087890123456', 'kevin@autoparts.co.id', 'Jl. Industri No. 90', 'Bekasi', '17530', 'active', '2025-07-30 23:49:18', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `role` enum('admin','manager','staff','viewer') DEFAULT 'staff',
  `status` enum('active','inactive') DEFAULT 'active',
  `last_login` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `username`, `email`, `password`, `role`, `status`, `last_login`, `created_at`, `updated_at`) VALUES
(1, 'admin', 'admin@warehouse.com', '0192023a7bbd73250516f069df18b500', 'admin', 'active', NULL, '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(2, 'manager', 'manager@warehouse.com', '0795151defba7a4b5dfa89170de46277', 'manager', 'active', NULL, '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(3, 'staff1', 'staff1@warehouse.com', 'de9bf5643eabf80f4a56fda3bbb84483', 'staff', 'active', NULL, '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(4, 'staff2', 'staff2@warehouse.com', 'de9bf5643eabf80f4a56fda3bbb84483', 'staff', 'active', NULL, '2025-07-30 23:49:18', '2025-07-30 23:49:18'),
(5, 'viewer', 'viewer@warehouse.com', '49e5e739ea41d635246cd9cd21af17c4', 'viewer', 'active', NULL, '2025-07-30 23:49:18', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Table structure for table `user_profiles`
--

CREATE TABLE `user_profiles` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `full_name` varchar(150) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `department` varchar(50) DEFAULT NULL,
  `hire_date` date DEFAULT NULL,
  `avatar` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `user_profiles`
--

INSERT INTO `user_profiles` (`id`, `user_id`, `full_name`, `phone`, `address`, `department`, `hire_date`, `avatar`) VALUES
(1, 1, 'Administrator System', '081111111111', NULL, 'IT Department', '2023-01-01', NULL),
(2, 2, 'Warehouse Manager', '082222222222', NULL, 'Warehouse', '2023-02-01', NULL),
(3, 3, 'Staff Gudang 1', '083333333333', NULL, 'Warehouse', '2023-03-01', NULL),
(4, 4, 'Staff Gudang 2', '084444444444', NULL, 'Warehouse', '2023-04-01', NULL),
(5, 5, 'Viewer Account', '085555555555', NULL, 'Management', '2023-05-01', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `warehouse_locations`
--

CREATE TABLE `warehouse_locations` (
  `id` int(11) NOT NULL,
  `location_code` varchar(20) NOT NULL,
  `location_name` varchar(100) NOT NULL,
  `zone` varchar(50) DEFAULT NULL,
  `capacity` int(11) DEFAULT 0,
  `current_utilization` int(11) DEFAULT 0,
  `temperature_controlled` tinyint(1) DEFAULT 0,
  `status` enum('active','maintenance','inactive') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `warehouse_locations`
--

INSERT INTO `warehouse_locations` (`id`, `location_code`, `location_name`, `zone`, `capacity`, `current_utilization`, `temperature_controlled`, `status`, `created_at`) VALUES
(1, 'A-01-01', 'Gudang Utama Zona A Rak 1', 'Electronics Zone', 1000, 0, 0, 'active', '2025-07-30 23:49:18'),
(2, 'A-01-02', 'Gudang Utama Zona A Rak 2', 'Electronics Zone', 1000, 0, 0, 'active', '2025-07-30 23:49:18'),
(3, 'B-01-01', 'Gudang Sekunder Zona B Rak 1', 'Clothing Zone', 800, 0, 0, 'active', '2025-07-30 23:49:18'),
(4, 'B-01-02', 'Gudang Sekunder Zona B Rak 2', 'Clothing Zone', 800, 0, 0, 'active', '2025-07-30 23:49:18'),
(5, 'C-01-01', 'Gudang Dingin Zona C Rak 1', 'Food Zone', 500, 0, 1, 'active', '2025-07-30 23:49:18'),
(6, 'C-01-02', 'Gudang Dingin Zona C Rak 2', 'Food Zone', 500, 0, 1, 'active', '2025-07-30 23:49:18'),
(7, 'D-01-01', 'Gudang Office Zona D Rak 1', 'Office Zone', 600, 0, 0, 'active', '2025-07-30 23:49:18');

-- --------------------------------------------------------

--
-- Structure for view `manager_order_view`
--
DROP TABLE IF EXISTS `manager_order_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `manager_order_view`  AS SELECT `sov`.`id` AS `id`, `sov`.`order_number` AS `order_number`, `sov`.`customer_id` AS `customer_id`, `sov`.`order_date` AS `order_date`, `sov`.`total_amount` AS `total_amount`, `sov`.`final_amount` AS `final_amount`, `sov`.`status` AS `status`, `sov`.`created_by` AS `created_by`, `c`.`name` AS `customer_name`, `c`.`customer_type` AS `customer_type`, `c`.`credit_limit` AS `credit_limit` FROM (`staff_order_view` `sov` join `customers` `c` on(`sov`.`customer_id` = `c`.`id`)) WHERE `sov`.`final_amount` >= 1000000WITH CASCADEDCHECK OPTION  ;

-- --------------------------------------------------------

--
-- Structure for view `product_stock_summary`
--
DROP TABLE IF EXISTS `product_stock_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `product_stock_summary`  AS SELECT `p`.`id` AS `id`, `p`.`sku` AS `sku`, `p`.`name` AS `product_name`, `p`.`unit_price` AS `unit_price`, `p`.`minimum_stock` AS `minimum_stock`, `c`.`name` AS `category_name`, `s`.`name` AS `supplier_name`, `s`.`contact_person` AS `supplier_contact`, coalesce(sum(`si`.`quantity`),0) AS `total_stock`, coalesce(sum(`si`.`reserved_quantity`),0) AS `reserved_stock`, coalesce(sum(`si`.`quantity`),0) - coalesce(sum(`si`.`reserved_quantity`),0) AS `available_stock`, CASE WHEN coalesce(sum(`si`.`quantity`),0) = 0 THEN 'OUT_OF_STOCK' WHEN coalesce(sum(`si`.`quantity`),0) <= `p`.`minimum_stock` THEN 'LOW_STOCK' ELSE 'IN_STOCK' END AS `stock_status` FROM (((`products` `p` left join `categories` `c` on(`p`.`category_id` = `c`.`id`)) left join `suppliers` `s` on(`p`.`supplier_id` = `s`.`id`)) left join `stock_inventory` `si` on(`p`.`id` = `si`.`product_id`)) WHERE `p`.`status` = 'active' GROUP BY `p`.`id`, `p`.`sku`, `p`.`name`, `p`.`unit_price`, `p`.`minimum_stock`, `c`.`name`, `s`.`name`, `s`.`contact_person` ;

-- --------------------------------------------------------

--
-- Structure for view `staff_order_view`
--
DROP TABLE IF EXISTS `staff_order_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `staff_order_view`  AS SELECT `orders`.`id` AS `id`, `orders`.`order_number` AS `order_number`, `orders`.`customer_id` AS `customer_id`, `orders`.`order_date` AS `order_date`, `orders`.`total_amount` AS `total_amount`, `orders`.`final_amount` AS `final_amount`, `orders`.`status` AS `status`, `orders`.`created_by` AS `created_by` FROM `orders` WHERE `orders`.`status` in ('pending','processing','shipped')WITH CASCADED CHECK OPTION  ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `audit_log`
--
ALTER TABLE `audit_log`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `customers`
--
ALTER TABLE `customers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `customer_code` (`customer_code`);

--
-- Indexes for table `orders`
--
ALTER TABLE `orders`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `order_number` (`order_number`),
  ADD KEY `idx_order_customer_date` (`customer_id`,`order_date`,`status`);

--
-- Indexes for table `order_details`
--
ALTER TABLE `order_details`
  ADD PRIMARY KEY (`id`),
  ADD KEY `product_id` (`product_id`),
  ADD KEY `idx_order_product_qty` (`order_id`,`product_id`,`quantity`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `sku` (`sku`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `supplier_id` (`supplier_id`);

--
-- Indexes for table `product_search_index`
--
ALTER TABLE `product_search_index`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_product_keywords` (`product_id`,`popularity_score`);

--
-- Indexes for table `product_tags`
--
ALTER TABLE `product_tags`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `product_tag_relations`
--
ALTER TABLE `product_tag_relations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_product_tag` (`product_id`,`tag_id`),
  ADD KEY `tag_id` (`tag_id`);

--
-- Indexes for table `purchase_orders`
--
ALTER TABLE `purchase_orders`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `po_number` (`po_number`),
  ADD KEY `supplier_id` (`supplier_id`);

--
-- Indexes for table `purchase_order_details`
--
ALTER TABLE `purchase_order_details`
  ADD PRIMARY KEY (`id`),
  ADD KEY `product_id` (`product_id`),
  ADD KEY `idx_po_product_status` (`po_id`,`product_id`,`quantity_received`);

--
-- Indexes for table `stock_inventory`
--
ALTER TABLE `stock_inventory`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_product_location_batch` (`product_id`,`location_id`,`batch_number`),
  ADD KEY `location_id` (`location_id`),
  ADD KEY `idx_stock_product_location` (`product_id`,`location_id`,`quantity`);

--
-- Indexes for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `location_id` (`location_id`),
  ADD KEY `idx_movement_product_date` (`product_id`,`movement_date`,`movement_type`);

--
-- Indexes for table `suppliers`
--
ALTER TABLE `suppliers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `user_profiles`
--
ALTER TABLE `user_profiles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `user_id` (`user_id`);

--
-- Indexes for table `warehouse_locations`
--
ALTER TABLE `warehouse_locations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `location_code` (`location_code`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `audit_log`
--
ALTER TABLE `audit_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `categories`
--
ALTER TABLE `categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `orders`
--
ALTER TABLE `orders`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `order_details`
--
ALTER TABLE `order_details`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1022;

--
-- AUTO_INCREMENT for table `product_search_index`
--
ALTER TABLE `product_search_index`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `product_tags`
--
ALTER TABLE `product_tags`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `product_tag_relations`
--
ALTER TABLE `product_tag_relations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `purchase_orders`
--
ALTER TABLE `purchase_orders`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `purchase_order_details`
--
ALTER TABLE `purchase_order_details`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `stock_inventory`
--
ALTER TABLE `stock_inventory`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1031;

--
-- AUTO_INCREMENT for table `stock_movements`
--
ALTER TABLE `stock_movements`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `suppliers`
--
ALTER TABLE `suppliers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `user_profiles`
--
ALTER TABLE `user_profiles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `warehouse_locations`
--
ALTER TABLE `warehouse_locations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `orders`
--
ALTER TABLE `orders`
  ADD CONSTRAINT `orders_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`);

--
-- Constraints for table `order_details`
--
ALTER TABLE `order_details`
  ADD CONSTRAINT `order_details_ibfk_1` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `order_details_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`);

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `products_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`),
  ADD CONSTRAINT `products_ibfk_2` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`id`);

--
-- Constraints for table `product_search_index`
--
ALTER TABLE `product_search_index`
  ADD CONSTRAINT `product_search_index_ibfk_1` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `product_tag_relations`
--
ALTER TABLE `product_tag_relations`
  ADD CONSTRAINT `product_tag_relations_ibfk_1` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `product_tag_relations_ibfk_2` FOREIGN KEY (`tag_id`) REFERENCES `product_tags` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `purchase_orders`
--
ALTER TABLE `purchase_orders`
  ADD CONSTRAINT `purchase_orders_ibfk_1` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`id`);

--
-- Constraints for table `purchase_order_details`
--
ALTER TABLE `purchase_order_details`
  ADD CONSTRAINT `purchase_order_details_ibfk_1` FOREIGN KEY (`po_id`) REFERENCES `purchase_orders` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `purchase_order_details_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`);

--
-- Constraints for table `stock_inventory`
--
ALTER TABLE `stock_inventory`
  ADD CONSTRAINT `stock_inventory_ibfk_1` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `stock_inventory_ibfk_2` FOREIGN KEY (`location_id`) REFERENCES `warehouse_locations` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD CONSTRAINT `stock_movements_ibfk_1` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`),
  ADD CONSTRAINT `stock_movements_ibfk_2` FOREIGN KEY (`location_id`) REFERENCES `warehouse_locations` (`id`);

--
-- Constraints for table `user_profiles`
--
ALTER TABLE `user_profiles`
  ADD CONSTRAINT `user_profiles_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
