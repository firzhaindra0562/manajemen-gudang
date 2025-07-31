<?php
session_start();
require_once 'config/db.php';

// Menangkap semua data dari form
$id = $_POST['id'];
$location_code = $_POST['location_code'];
$location_name = $_POST['location_name'];
$zone = $_POST['zone'];
$capacity = $_POST['capacity'];
$status = $_POST['status'];
// Menangani nilai checkbox. Jika dicentang, nilainya 1, jika tidak, 0.
$temperature_controlled = isset($_POST['temperature_controlled']) ? 1 : 0;

// Proses Simpan Data Baru
if (isset($_POST['save'])) {
    $stmt = $mysqli->prepare("INSERT INTO warehouse_locations (location_code, location_name, zone, capacity, temperature_controlled, status) VALUES (?, ?, ?, ?, ?, ?)");
    $stmt->bind_param("sssiis", $location_code, $location_name, $zone, $capacity, $temperature_controlled, $status);
    
    if ($stmt->execute()) {
        $_SESSION['message'] = "Lokasi baru berhasil ditambahkan!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menambahkan lokasi: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

// Proses Update Data
if (isset($_POST['update'])) {
    $stmt = $mysqli->prepare("UPDATE warehouse_locations SET location_code=?, location_name=?, zone=?, capacity=?, temperature_controlled=?, status=? WHERE id=?");
    $stmt->bind_param("sssiisi", $location_code, $location_name, $zone, $capacity, $temperature_controlled, $status, $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Data lokasi berhasil diperbarui!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal memperbarui data: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

// Redirect kembali ke halaman utama lokasi
header('Location: locations.php');
exit();
?>