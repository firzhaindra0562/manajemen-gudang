<?php
session_start();
require_once 'config/db.php';

// Proses Simpan Data Baru
if (isset($_POST['save'])) {
    $stmt = $mysqli->prepare("INSERT INTO customers (customer_code, name, email, phone, address, city, postal_code, customer_type, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->bind_param(
        "sssssssss",
        $_POST['customer_code'],
        $_POST['name'],
        $_POST['email'],
        $_POST['phone'],
        $_POST['address'],
        $_POST['city'],
        $_POST['postal_code'],
        $_POST['customer_type'],
        $_POST['status']
    );

    if ($stmt->execute()) {
        $_SESSION['message'] = "Pelanggan baru berhasil ditambahkan!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menambahkan pelanggan: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

// Proses Update Data
if (isset($_POST['update'])) {
    $stmt = $mysqli->prepare("UPDATE customers SET customer_code=?, name=?, email=?, phone=?, address=?, city=?, postal_code=?, customer_type=?, status=? WHERE id=?");
    $stmt->bind_param(
        "sssssssssi",
        $_POST['customer_code'],
        $_POST['name'],
        $_POST['email'],
        $_POST['phone'],
        $_POST['address'],
        $_POST['city'],
        $_POST['postal_code'],
        $_POST['customer_type'],
        $_POST['status'],
        $_POST['id']
    );

    if ($stmt->execute()) {
        $_SESSION['message'] = "Data pelanggan berhasil diperbarui!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal memperbarui data: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

header('Location: customers.php');
exit();
?>