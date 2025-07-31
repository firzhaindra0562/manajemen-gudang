<?php
include 'includes/header.php';

if (!isset($_GET['id']) || empty($_GET['id'])) {
    header("Location: purchase_orders.php");
    exit();
}

$po_id = (int)$_GET['id'];

// 1. Ambil data master PO
$sql_po = "SELECT po.*, s.name as supplier_name, s.contact_person, s.phone as supplier_phone, s.address as supplier_address
           FROM purchase_orders po
           JOIN suppliers s ON po.supplier_id = s.id
           WHERE po.id = ?";
$stmt_po = $mysqli->prepare($sql_po);
$stmt_po->bind_param("i", $po_id);
$stmt_po->execute();
$result_po = $stmt_po->get_result();
$po = $result_po->fetch_assoc();

if (!$po) {
    header("Location: purchase_orders.php");
    exit();
}

// 2. Ambil data detail PO (item produk)
$sql_details = "SELECT pod.*, p.name as product_name, p.sku
                FROM purchase_order_details pod
                JOIN products p ON pod.product_id = p.id
                WHERE pod.po_id = ?";
$stmt_details = $mysqli->prepare($sql_details);
$stmt_details->bind_param("i", $po_id);
$stmt_details->execute();
$result_details = $stmt_details->get_result();
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">Detail PO: <span class="text-indigo-600"><?php echo htmlspecialchars($po['po_number']); ?></span></h1>
    <a href="purchase_orders.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali ke Daftar PO
    </a>
</div>

<div class="bg-white shadow-md rounded-lg p-6">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6 pb-6 border-b">
        <div>
            <h3 class="text-lg font-semibold text-gray-800">Supplier</h3>
            <p class="text-gray-600 font-bold"><?php echo htmlspecialchars($po['supplier_name']); ?></p>
            <p class="text-gray-600"><?php echo htmlspecialchars($po['supplier_address']); ?></p>
            <p class="text-gray-600">Kontak: <?php echo htmlspecialchars($po['contact_person']) . ' (' . htmlspecialchars($po['supplier_phone']) . ')'; ?></p>
        </div>
        <div>
            <h3 class="text-lg font-semibold text-gray-800">Info Pesanan</h3>
            <p class="text-gray-600"><strong>Tgl. Pesan:</strong> <?php echo date('d F Y', strtotime($po['order_date'])); ?></p>
            <p class="text-gray-600"><strong>Harapan Tiba:</strong> <?php echo date('d F Y', strtotime($po['expected_delivery'])); ?></p>
            <p class="text-gray-600"><strong>Status:</strong> <span class="font-semibold text-yellow-700"><?php echo ucfirst(htmlspecialchars($po['status'])); ?></span></p>
        </div>
    </div>

    <h3 class="text-lg font-semibold text-gray-800 mb-4">Item yang Dipesan</h3>
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Produk</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Dipesan</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Diterima</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Biaya Satuan</th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase">Subtotal</th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                <?php 
                $grand_total = 0;
                while ($item = $result_details->fetch_assoc()): 
                    $grand_total += $item['line_total'];
                ?>
                <tr class="hover:bg-gray-50">
                    <td class="px-4 py-2 whitespace-nowrap text-sm font-medium text-gray-900"><?php echo htmlspecialchars($item['product_name']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo number_format($item['quantity_ordered']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo number_format($item['quantity_received']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-500"><?php echo format_rupiah($item['unit_cost']); ?></td>
                    <td class="px-4 py-2 whitespace-nowrap text-sm text-right font-semibold text-gray-800"><?php echo format_rupiah($item['line_total']); ?></td>
                </tr>
                <?php endwhile; ?>
            </tbody>
            <tfoot class="bg-gray-50">
                <tr>
                    <td colspan="4" class="px-4 py-2 text-right text-lg font-bold text-gray-900">Total Pembelian</td>
                    <td class="px-4 py-2 text-right text-lg font-bold text-gray-900"><?php echo format_rupiah($grand_total); ?></td>
                </tr>
            </tfoot>
        </table>
    </div>
</div>

<?php include 'includes/footer.php'; ?>