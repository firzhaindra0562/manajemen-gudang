<?php
session_start();
require_once 'config/db.php';

// Menangkap semua data dari form
$id = $_POST['id'];
$name = $_POST['name'];
$contact_person = $_POST['contact_person'];
$phone = $_POST['phone'];
$email = $_POST['email'];
$address = $_POST['address'];
$city = $_POST['city'];
$postal_code = $_POST['postal_code'];
$status = $_POST['status'];

// Proses Simpan Data Baru
if (isset($_POST['save'])) {
    $stmt = $mysqli->prepare("INSERT INTO suppliers (name, contact_person, phone, email, address, city, postal_code, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->bind_param("ssssssss", $name, $contact_person, $phone, $email, $address, $city, $postal_code, $status);
    
    if ($stmt->execute()) {
        $_SESSION['message'] = "Supplier baru berhasil ditambahkan!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal menambahkan supplier: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

// Proses Update Data
if (isset($_POST['update'])) {
    $stmt = $mysqli->prepare("UPDATE suppliers SET name=?, contact_person=?, phone=?, email=?, address=?, city=?, postal_code=?, status=? WHERE id=?");
    $stmt->bind_param("ssssssssi", $name, $contact_person, $phone, $email, $address, $city, $postal_code, $status, $id);

    if ($stmt->execute()) {
        $_SESSION['message'] = "Data supplier berhasil diperbarui!";
        $_SESSION['msg_type'] = "success";
    } else {
        $_SESSION['message'] = "Gagal memperbarui data: " . $stmt->error;
        $_SESSION['msg_type'] = "danger";
    }
    $stmt->close();
}

// Redirect kembali ke halaman utama supplier
header('Location: suppliers.php');
exit();
?>