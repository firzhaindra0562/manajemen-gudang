<?php include 'includes/header.php'; ?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">👥 Daftar Pelanggan</h1>
    <a href="customer_form.php" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-plus-circle-fill mr-2"></i> Tambah Pelanggan
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
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Kode</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Nama Pelanggan</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Telepon</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tipe</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Aksi</th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                <?php
                $result = $mysqli->query("SELECT id, customer_code, name, phone, customer_type, status FROM customers ORDER BY name ASC");
                if ($result->num_rows > 0) :
                    while ($row = $result->fetch_assoc()) : ?>
                        <tr class="hover:bg-gray-50">
                            <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-700"><?php echo htmlspecialchars($row['customer_code']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900"><?php echo htmlspecialchars($row['name']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><?php echo htmlspecialchars($row['phone']); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><?php echo ucfirst(htmlspecialchars($row['customer_type'])); ?></td>
                            <td class="px-6 py-4 whitespace-nowrap">
                                <?php
                                $status = $row['status'];
                                $badge_class = ($status == 'active') ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800';
                                echo '<span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full ' . $badge_class . '">' . ucfirst($status) . '</span>';
                                ?>
                            </td>
                            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                                <a href="customer_form.php?id=<?php echo $row['id']; ?>" class="text-indigo-600 hover:text-indigo-900" title="Edit"><i class="bi bi-pencil-square"></i></a>
                                <a href="customer_delete.php?id=<?php echo $row['id']; ?>" class="text-red-600 hover:text-red-900" title="Hapus" onclick="return confirm('Yakin ingin menghapus pelanggan ini?');"><i class="bi bi-trash-fill"></i></a>
                            </td>
                        </tr>
                <?php endwhile; else: ?>
                    <tr>
                        <td colspan="6" class="text-center py-4 text-gray-500">Belum ada data pelanggan.</td>
                    </tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>

<?php include 'includes/footer.php'; ?>