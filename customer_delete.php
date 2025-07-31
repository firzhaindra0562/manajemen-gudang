<?php
session_start();
require_once 'config/db.php';

if (isset($_GET['id'])) {
    $id = $_GET['id'];
    
    // Foreign key di tabel 'orders' diset `ON DELETE RESTRICT`.
    $stmt = $mysqli->prepare("DELETE FROM customers WHERE id=?");
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Pelanggan berhasil dihapus!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menghapus. Pelanggan ini kemungkinan sudah memiliki data pesanan (order).";
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

header('Location: customers.php');
exit();
?>