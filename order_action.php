<?php
session_start();
require_once 'config/db.php';

if (isset($_POST['save_order'])) {
    $customer_id = $_POST['customer_id'];
    $order_number = $_POST['order_number'];
    $products = isset($_POST['products']) ? $_POST['products'] : [];

    // Validasi dasar
    if (empty($customer_id) || empty($products)) {
        $_SESSION['message'] = "Pelanggan dan minimal satu produk harus dipilih.";
        $_SESSION['msg_type'] = "danger";
        header('Location: order_form.php');
        exit();
    }

    // Mulai transaksi database
    $mysqli->begin_transaction();

    try {
        // 1. Insert ke tabel master 'orders'
        // Total akan diupdate oleh trigger, tapi kita bisa masukan 0 sebagai nilai awal.
        $stmt_order = $mysqli->prepare("INSERT INTO orders (order_number, customer_id, status, created_by) VALUES (?, ?, 'pending', 'staff1')");
        $stmt_order->bind_param("si", $order_number, $customer_id);
        $stmt_order->execute();
        
        // Ambil ID dari order yang baru saja dibuat
        $order_id = $mysqli->insert_id;

        if ($order_id == 0) {
            throw new Exception("Gagal membuat order master.");
        }

        // 2. Loop dan insert setiap produk ke 'order_details'
        $stmt_details = $mysqli->prepare("INSERT INTO order_details (order_id, product_id, quantity, unit_price, line_total) VALUES (?, ?, ?, ?, ?)");
        
        foreach ($products as $product) {
            $product_id = $product['id'];
            $quantity = $product['quantity'];
            $unit_price = $product['unit_price'];
            $line_total = $quantity * $unit_price;

            $stmt_details->bind_param("iiidd", $order_id, $product_id, $quantity, $unit_price, $line_total);
            $stmt_details->execute();
        }

        // Jika semua berhasil, commit transaksi
        $mysqli->commit();

        $_SESSION['message'] = "Pesanan berhasil dibuat dengan nomor " . $order_number;
        $_SESSION['msg_type'] = "success";
        header('Location: orders.php');

    } catch (Exception $e) {
        // Jika ada error, rollback semua perubahan
        $mysqli->rollback();

        $_SESSION['message'] = "Terjadi kesalahan saat menyimpan pesanan: " . $e->getMessage();
        $_SESSION['msg_type'] = "danger";
        header('Location: order_form.php');
    }
    exit();
}
?>