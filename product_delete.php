<?php
session_start();
require_once 'config/db.php';

if (isset($_GET['id'])) {
    $id = $_GET['id'];
    
    // Perhatian: Foreign key constraints (ON DELETE RESTRICT) akan mencegah penghapusan
    // jika produk ini sudah terkait dengan order_details atau purchase_order_details.
    // Ini adalah perilaku yang aman. Anda bisa menambahkan penanganan error yang lebih baik.
    $stmt = $mysqli->prepare("DELETE FROM products WHERE id=?");
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Produk berhasil dihapus!";
        $_SESSION['msg_type'] = "success";
    } else {
        // Pesan error jika foreign key constraint gagal
        $_SESSION['message'] = "Gagal menghapus produk. Mungkin produk ini sudah terkait dengan data order atau pembelian.";
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
    header('Location: products.php');
    exit();
}
?>