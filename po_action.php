<?php
session_start();
require_once 'config/db.php';

if (isset($_POST['save_po'])) {
    $supplier_id = $_POST['supplier_id'];
    $po_number = $_POST['po_number'];
    $expected_delivery = $_POST['expected_delivery'];
    $products = isset($_POST['products']) ? $_POST['products'] : [];

    if (empty($supplier_id) || empty($products)) {
        $_SESSION['message'] = "Supplier dan minimal satu produk harus dipilih.";
        $_SESSION['msg_type'] = "danger";
        header('Location: po_form.php');
        exit();
    }

    $total_amount = 0;
    foreach ($products as $product) {
        $total_amount += $product['unit_cost'] * $product['quantity'];
    }

    $mysqli->begin_transaction();

    try {
        // 1. Insert ke tabel master 'purchase_orders'
        $stmt_po = $mysqli->prepare("INSERT INTO purchase_orders (po_number, supplier_id, expected_delivery, total_amount, status, created_by) VALUES (?, ?, ?, ?, 'pending', 'manager')");
        $stmt_po->bind_param("sisd", $po_number, $supplier_id, $expected_delivery, $total_amount);
        $stmt_po->execute();
        
        $po_id = $mysqli->insert_id;

        if ($po_id == 0) {
            throw new Exception("Gagal membuat purchase order master.");
        }

        // 2. Loop dan insert setiap produk ke 'purchase_order_details'
        $stmt_details = $mysqli->prepare("INSERT INTO purchase_order_details (po_id, product_id, quantity_ordered, unit_cost, line_total) VALUES (?, ?, ?, ?, ?)");
        
        foreach ($products as $product) {
            $product_id = $product['id'];
            $quantity_ordered = $product['quantity'];
            $unit_cost = $product['unit_cost'];
            $line_total = $quantity_ordered * $unit_cost;

            $stmt_details->bind_param("iiidd", $po_id, $product_id, $quantity_ordered, $unit_cost, $line_total);
            $stmt_details->execute();
        }

        $mysqli->commit();

        $_SESSION['message'] = "Purchase Order berhasil dibuat dengan nomor " . $po_number;
        $_SESSION['msg_type'] = "success";
        header('Location: purchase_orders.php');

    } catch (Exception $e) {
        $mysqli->rollback();
        $_SESSION['message'] = "Terjadi kesalahan saat menyimpan PO: " . $e->getMessage();
        $_SESSION['msg_type'] = "danger";
        header('Location: po_form.php');
    }
    exit();
}
?>