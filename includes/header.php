<?php
// Mulai session jika belum ada. Berguna untuk notifikasi.
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}
require_once 'config/db.php';
?>
<!DOCTYPE html>
<html lang="id" class="bg-gray-50">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manajemen Gudang</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
        /* Anda bisa menambahkan custom style base di sini jika perlu */
    </style>
</head>
<body class="font-sans text-gray-800">
    <nav class="bg-indigo-600 shadow-lg">
    <div class="container mx-auto px-4">
        <div class="flex justify-between items-center py-3">
            <a class="text-white text-xl font-bold flex items-center" href="index.php">
                <i class="bi bi-box-seam-fill mr-2"></i>GudangKu
            </a>
            <div class="hidden md:flex items-center space-x-2">
                
                <a href="index.php" class="py-2 px-3 rounded-md text-sm font-medium text-indigo-100 hover:bg-indigo-500 hover:text-white">Dashboard</a>

                <div class="relative">
                    <button id="masterDataBtn" class="flex items-center py-2 px-3 rounded-md text-sm font-medium text-indigo-100 hover:bg-indigo-500 hover:text-white focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-indigo-600 focus:ring-white">
                        <span>Master Data</span>
                        <i class="bi bi-chevron-down ml-1"></i>
                    </button>
                    <div id="masterDataMenu" class="absolute left-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 z-20 hidden">
                        <a href="products.php" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Produk</a>
                        <a href="categories.php" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Kategori</a>
                        <a href="suppliers.php" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Supplier</a>
                        <a href="locations.php" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Lokasi Gudang</a>
                        <a href="customers.php" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">Pelanggan</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</nav>
    <main class="container mx-auto px-4 mt-6">