<?php
session_start();
require_once 'config/db.php';

// Proses Simpan Data Baru
if (isset($_POST['save'])) {
    $sku = $_POST['sku'];
    $name = $_POST['name'];
    $description = $_POST['description'];
    $category_id = $_POST['category_id'];
    $supplier_id = $_POST['supplier_id'];
    $unit_price = $_POST['unit_price'];
    $minimum_stock = $_POST['minimum_stock'];
    $weight = $_POST['weight'];
    $status = $_POST['status'];

    $stmt = $mysqli->prepare("INSERT INTO products (sku, name, description, category_id, supplier_id, unit_price, minimum_stock, weight, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->bind_param("sssiidids", $sku, $name, $description, $category_id, $supplier_id, $unit_price, $minimum_stock, $weight, $status);
    
    if ($stmt->execute()) {
        $_SESSION['message'] = "Produk berhasil ditambahkan!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menambahkan produk: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
    header('Location: products.php');
    exit();
}

// Proses Update Data
if (isset($_POST['update'])) {
    $id = $_POST['id'];
    $sku = $_POST['sku'];
    $name = $_POST['name'];
    $description = $_POST['description'];
    $category_id = $_POST['category_id'];
    $supplier_id = $_POST['supplier_id'];
    $unit_price = $_POST['unit_price'];
    $minimum_stock = $_POST['minimum_stock'];
    $weight = $_POST['weight'];
    $status = $_POST['status'];

    $stmt = $mysqli->prepare("UPDATE products SET sku=?, name=?, description=?, category_id=?, supplier_id=?, unit_price=?, minimum_stock=?, weight=?, status=? WHERE id=?");
    $stmt->bind_param("sssiididsi", $sku, $name, $description, $category_id, $supplier_id, $unit_price, $minimum_stock, $weight, $status, $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Data produk berhasil diperbarui!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal memperbarui data: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
    header('Location: products.php');
    exit();
}
?>