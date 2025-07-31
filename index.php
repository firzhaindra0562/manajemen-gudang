<?php
include 'includes/header.php';

// 1. Ambil data untuk kartu KPI (Key Performance Indicators)
// Memanggil Function dari database
$total_products_result = $mysqli->query("SELECT GetTotalActiveProducts() as total");
$total_products = $total_products_result->fetch_assoc()['total'];

// Query sederhana
$total_suppliers = $mysqli->query("SELECT COUNT(id) as total FROM suppliers WHERE status = 'active'")->fetch_assoc()['total'];
$total_customers = $mysqli->query("SELECT COUNT(id) as total FROM customers WHERE status = 'active'")->fetch_assoc()['total'];
$pending_orders = $mysqli->query("SELECT COUNT(id) as total FROM orders WHERE status = 'pending'")->fetch_assoc()['total'];


// 2. Ambil data untuk laporan stok rendah (Memanggil Stored Procedure)
$low_stock_items_result = $mysqli->query("CALL GenerateLowStockReport()");
// Penting: Bersihkan hasil query sebelumnya jika menggunakan stored procedure
while ($mysqli->next_result()) {;} 


// 3. Ambil data 5 pesanan penjualan terakhir
$recent_orders_result = $mysqli->query("SELECT o.order_number, o.final_amount, c.name as customer_name 
                                         FROM orders o JOIN customers c ON o.customer_id = c.id 
                                         ORDER BY o.order_date DESC LIMIT 5");

?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">📊 Dashboard</h1>
</div>

<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
    <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
        <div>
            <p class="text-sm font-medium text-gray-500">Produk Aktif</p>
            <p class="text-3xl font-bold text-gray-800"><?php echo number_format($total_products); ?></p>
        </div>
        <div class="bg-blue-100 text-blue-600 rounded-full p-3">
            <i class="bi bi-box-seam-fill text-2xl"></i>
        </div>
    </div>
    <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
        <div>
            <p class="text-sm font-medium text-gray-500">Supplier Aktif</p>
            <p class="text-3xl font-bold text-gray-800"><?php echo number_format($total_suppliers); ?></p>
        </div>
        <div class="bg-green-100 text-green-600 rounded-full p-3">
            <i class="bi bi-truck text-2xl"></i>
        </div>
    </div>
    <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
        <div>
            <p class="text-sm font-medium text-gray-500">Pelanggan Aktif</p>
            <p class="text-3xl font-bold text-gray-800"><?php echo number_format($total_customers); ?></p>
        </div>
        <div class="bg-purple-100 text-purple-600 rounded-full p-3">
            <i class="bi bi-people-fill text-2xl"></i>
        </div>
    </div>
    <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
        <div>
            <p class="text-sm font-medium text-gray-500">Order Pending</p>
            <p class="text-3xl font-bold text-gray-800"><?php echo number_format($pending_orders); ?></p>
        </div>
        <div class="bg-yellow-100 text-yellow-600 rounded-full p-3">
            <i class="bi bi-cart-x-fill text-2xl"></i>
        </div>
    </div>
</div>

<div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <div class="bg-white p-6 rounded-lg shadow-md">
        <h3 class="text-lg font-semibold text-gray-800 mb-4">⚠️ Laporan Stok Rendah</h3>
        <div class="overflow-y-auto h-80">
            <table class="min-w-full">
                <thead class="bg-gray-50 sticky top-0">
                    <tr>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Produk</th>
                        <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Stok</th>
                        <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Min.</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                    <?php if ($low_stock_items_result->num_rows > 0): ?>
                        <?php while ($item = $low_stock_items_result->fetch_assoc()): 
                            $status_color = 'text-yellow-600';
                            if ($item['status'] == 'CRITICAL_LOW') $status_color = 'text-orange-600';
                            if ($item['status'] == 'OUT_OF_STOCK') $status_color = 'text-red-600';
                        ?>
                        <tr class="hover:bg-gray-50">
                            <td class="px-4 py-2 whitespace-nowrap text-sm font-medium text-gray-900"><?php echo htmlspecialchars($item['product_name']); ?></td>
                            <td class="px-4 py-2 whitespace-nowrap text-sm text-right font-bold <?php echo $status_color; ?>"><?php echo number_format($item['current_stock']); ?></td>
                            <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo number_format($item['minimum_stock']); ?></td>
                        </tr>
                        <?php endwhile; ?>
                    <?php else: ?>
                        <tr><td colspan="3" class="text-center py-4 text-gray-500">Stok aman! Tidak ada produk di bawah batas minimum.</td></tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>

    <div class="bg-white p-6 rounded-lg shadow-md">
        <h3 class="text-lg font-semibold text-gray-800 mb-4">🛒 5 Pesanan Penjualan Terbaru</h3>
        <div class="overflow-y-auto h-80">
            <ul class="divide-y divide-gray-200">
                <?php if ($recent_orders_result->num_rows > 0): ?>
                    <?php while ($order = $recent_orders_result->fetch_assoc()): ?>
                    <li class="py-3 flex justify-between items-center">
                        <div>
                            <p class="text-sm font-medium text-indigo-600"><?php echo htmlspecialchars($order['order_number']); ?></p>
                            <p class="text-sm text-gray-500"><?php echo htmlspecialchars($order['customer_name']); ?></p>
                        </div>
                        <p class="text-sm font-semibold text-gray-800"><?php echo format_rupiah($order['final_amount']); ?></p>
                    </li>
                    <?php endwhile; ?>
                <?php else: ?>
                    <li class="text-center py-4 text-gray-500">Belum ada pesanan.</li>
                <?php endif; ?>
            </ul>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>