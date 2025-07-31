<?php
session_start();
require_once 'config/db.php';

if (isset($_GET['id'])) {
    $id = $_GET['id'];
    
    // Menggunakan prepared statement untuk keamanan
    $stmt = $mysqli->prepare("DELETE FROM suppliers WHERE id=?");
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Supplier berhasil dihapus!";
        $_SESSION['msg_type'] = "success";
    } else {
        // Pesan error jika foreign key constraint gagal (supplier terhubung ke produk)
        $_SESSION['message'] = "Gagal menghapus. Supplier ini mungkin terhubung dengan data produk.";
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

header('Location: suppliers.php');
exit();
?>