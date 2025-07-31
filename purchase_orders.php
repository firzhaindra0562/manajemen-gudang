<?php include 'includes/header.php'; ?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">采购 Pesanan Pembelian (PO)</h1>
    <a href="po_form.php" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-plus-circle-fill mr-2"></i> Buat PO Baru
    </a>
</div>

<?php
if (isset($_SESSION['message'])) {
    $bgColor = $_SESSION['msg_type'] == 'success' ? 'bg-green-100 border-green-400 text-green-700' : 'bg-red-100 border-red-400 text-red-700';
    echo '<div class="' . $bgColor . ' border px-4 py-3 rounded-lg relative mb-4" role="alert">' . htmlspecialchars($_SESSION['message']) . '</div>';
    unset($_SESSION['message']);
    unset($_SESSION['msg_type']);
}
?>

<div class="bg-white shadow-md rounded-lg overflow-hidden">
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">No. PO</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Supplier</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tgl. Pesan</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tgl. Harapan Tiba</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Total</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Aksi</th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                <?php
                // Query dengan JOIN ke tabel suppliers
                $sql = "SELECT po.id, po.po_number, po.order_date, po.expected_delivery, po.total_amount, po.status, s.name as supplier_name 
                        FROM purchase_orders po
                        JOIN suppliers s ON po.supplier_id = s.id
                        ORDER BY po.order_date DESC";
                $result = $mysqli->query($sql);

                if ($result->num_rows > 0) :
                    while ($row = $result->fetch_assoc()) : ?>
                        <tr class="hover:bg-gray-50">
                            <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-indigo-700"><?php echo htmlspecialchars($row['po_number']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900"><?php echo htmlspecialchars($row['supplier_name']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><?php echo date('d M Y', strtotime($row['order_date'])); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><?php echo date('d M Y', strtotime($row['expected_delivery'])); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><?php echo format_rupiah($row['total_amount']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap">
                                <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800">
                                    <?php echo ucfirst(htmlspecialchars($row['status'])); ?>
                                </span>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                <a href="po_view.php?id=<?php echo $row['id']; ?>" class="text-blue-600 hover:text-blue-900" title="Lihat Detail"><i class="bi bi-eye-fill"></i></a>
                            </td>
                        </tr>
                <?php endwhile; else: ?>
                    <tr>
                        <td colspan="7" class="text-center py-4 text-gray-500">Belum ada data pesanan pembelian.</td>
                    </tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>

<?php include 'includes/footer.php'; ?>