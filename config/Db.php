<?php
// Konfigurasi koneksi database
define('DB_SERVER', 'localhost');
define('DB_USERNAME', 'root'); // Ganti dengan username database Anda
define('DB_PASSWORD', ''); // Ganti dengan password database Anda
define('DB_NAME', 'warehouse_management');

// Membuat koneksi ke database
$mysqli = new mysqli(DB_SERVER, DB_USERNAME, DB_PASSWORD, DB_NAME);

// Cek koneksi
if ($mysqli === false) {
    die("ERROR: Tidak dapat terhubung ke database. " . $mysqli->connect_error);
}

// Set karakter set ke utf8mb4 untuk mendukung karakter internasional
$mysqli->set_charset("utf8mb4");

// Fungsi untuk format Rupiah
function format_rupiah($number) {
    return 'Rp ' . number_format($number, 0, ',', '.');
}
?>