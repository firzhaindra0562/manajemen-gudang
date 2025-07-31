<?php
include 'includes/header.php';

// Cek apakah ID order ada di URL
if (!isset($_GET['id']) || empty($_GET['id'])) {
    // Redirect jika tidak ada ID
    $_SESSION['message'] = "Order tidak ditemukan.";
    $_SESSION['msg_type'] = "danger";
    header("Location: orders.php");
    exit();
}

$order_id = (int)$_GET['id'];

// 1. Ambil data master order
$sql_order = "SELECT o.*, c.name as customer_name, c.email as customer_email, c.phone as customer_phone, c.address as customer_address
              FROM orders o
              JOIN customers c ON o.customer_id = c.id
              WHERE o.id = ?";
$stmt_order = $mysqli->prepare($sql_order);
$stmt_order->bind_param("i", $order_id);
$stmt_order->execute();
$result_order = $stmt_order->get_result();
$order = $result_order->fetch_assoc();

if (!$order) {
    $_SESSION['message'] = "Order dengan ID $order_id tidak ditemukan.";
    $_SESSION['msg_type'] = "danger";
    header("Location: orders.php");
    exit();
}

// 2. Ambil data detail order (item produk)
$sql_details = "SELECT od.*, p.name as product_name, p.sku
                FROM order_details od
                JOIN products p ON od.product_id = p.id
                WHERE od.order_id = ?";
$stmt_details = $mysqli->prepare($sql_details);
$stmt_details->bind_param("i", $order_id);
$stmt_details->execute();
$result_details = $stmt_details->get_result();

?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">Detail Pesanan: <span class="text-indigo-600"><?php echo htmlspecialchars($order['order_number']); ?></span></h1>
    <a href="orders.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali ke Daftar Order
    </a>
</div>

<div class="bg-white shadow-md rounded-lg p-6">
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6 pb-6 border-b">
        <div>
            <h3 class="text-lg font-semibold text-gray-800">Pelanggan</h3>
            <p class="text-gray-600 font-bold"><?php echo htmlspecialchars($order['customer_name']); ?></p>
            <p class="text-gray-600"><?php echo htmlspecialchars($order['customer_address']); ?></p>
            <p class="text-gray-600"><?php echo htmlspecialchars($order['customer_phone']); ?></p>
            <p class="text-gray-600"><?php echo htmlspecialchars($order['customer_email']); ?></p>
        </div>
        <div>
            <h3 class="text-lg font-semibold text-gray-800">Info Pesanan</h3>
            <p class="text-gray-600"><strong>Tanggal:</strong> <?php echo date('d F Y, H:i', strtotime($order['order_date'])); ?></p>
            <p class="text-gray-600"><strong>Status:</strong> <span class="font-semibold text-blue-700"><?php echo ucfirst(htmlspecialchars($order['status'])); ?></span></p>
             <p class="text-gray-600"><strong>Dibuat Oleh:</strong> <?php echo htmlspecialchars($order['created_by']); ?></p>
        </div>
        <div>
            <h3 class="text-lg font-semibold text-gray-800">Catatan</h3>
            <p class="text-gray-600 italic"><?php echo !empty($order['notes']) ? htmlspecialchars($order['notes']) : 'Tidak ada catatan.'; ?></p>
        </div>
    </div>

    <h3 class="text-lg font-semibold text-gray-800 mb-4">Item yang Dipesan</h3>
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SKU</th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Produk</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Jumlah</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Harga Satuan</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Subtotal</th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                <?php while ($item = $result_details->fetch_assoc()): ?>
                <tr class="hover:bg-gray-50">
                    <td class="px-4 py-2 whitespace-nowrap text-sm font-mono text-gray-700"><?php echo htmlspecialchars($item['sku']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm font-medium text-gray-900"><?php echo htmlspecialchars($item['product_name']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo number_format($item['quantity']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo format_rupiah($item['unit_price']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right font-semibold text-gray-800"><?php echo format_rupiah($item['line_total']); ?></td>
                </tr>
                <?php endwhile; ?>
            </tbody>
            <tfoot class="bg-gray-50">
                <tr>
                    <td colspan="4" class="px-4 py-2 text-right font-semibold text-gray-700">Subtotal</td>
                    <td class="px-4 py-2 text-right font-semibold text-gray-800"><?php echo format_rupiah($order['total_amount']); ?></td>
                </tr>
                <tr>
                    <td colspan="4" class="px-4 py-2 text-right font-semibold text-gray-700">Pajak (10%)</td>
                    <td class="px-4 py-2 text-right font-semibold text-gray-800"><?php echo format_rupiah($order['tax_amount']); ?></td>
                </tr>
                <tr>
                    <td colspan="4" class="px-4 py-2 text-right text-lg font-bold text-gray-900">Total Akhir</td>
                    <td class="px-4 py-2 text-right text-lg font-bold text-gray-900"><?php echo format_rupiah($order['final_amount']); ?></td>
                </tr>
            </tfoot>
        </table>
    </div>
</div>

<?php include 'includes/footer.php'; ?>