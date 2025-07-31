<?php
session_start();
require_once 'config/db.php';

if (isset($_GET['id'])) {
    $id = $_GET['id'];
    
    // Perhatian: Menghapus lokasi bisa gagal jika terhubung dengan riwayat pergerakan stok
    // atau jika ada aturan lain di database.
    $stmt = $mysqli->prepare("DELETE FROM warehouse_locations WHERE id=?");
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Lokasi berhasil dihapus!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menghapus. Lokasi ini kemungkinan masih terhubung dengan data stok atau riwayat pergerakan barang.";
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

header('Location: locations.php');
exit();
?>