<?php
// ... (PHP code di bagian atas tetap sama, tidak perlu diubah)
include 'includes/header.php';

// Inisialisasi variabel untuk form
$id = 0;
// ... (sisa kode inisialisasi dan pengambilan data mode edit tetap sama)
$sku = '';
$name = '';
$description = '';
$category_id = '';
$supplier_id = '';
$unit_price = '';
$minimum_stock = 10;
$weight = 0;
$status = 'active';
$update = false;

if (isset($_GET['id'])) {
    $id = $_GET['id'];
    $update = true;
    $result = $mysqli->query("SELECT * FROM products WHERE id=$id") or die($mysqli->error);
    if ($result->num_rows == 1) {
        $row = $result->fetch_assoc();
        extract($row);
    }
}
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700"><?php echo $update ? '✏️ Edit Produk' : '✨ Tambah Produk Baru'; ?></h1>
    <a href="products.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali
    </a>
</div>

<div class="bg-white shadow-md rounded-lg p-6">
    <form action="product_action.php" method="POST">
        <input type="hidden" name="id" value="<?php echo $id; ?>">
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
                <label for="name" class="block text-sm font-medium text-gray-700">Nama Produk</label>
                <input type="text" name="name" id="name" value="<?php echo htmlspecialchars($name); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="sku" class="block text-sm font-medium text-gray-700">SKU (Stock Keeping Unit)</label>
                <input type="text" name="sku" id="sku" value="<?php echo htmlspecialchars($sku); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>

        <div class="mt-6">
            <label for="description" class="block text-sm font-medium text-gray-700">Deskripsi</label>
            <textarea name="description" id="description" rows="3" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500"><?php echo htmlspecialchars($description); ?></textarea>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-6">
             <div>
                <label for="category_id" class="block text-sm font-medium text-gray-700">Kategori</label>
                <select name="category_id" id="category_id" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="">Pilih Kategori</option>
                    <?php
                    $categories = $mysqli->query("SELECT id, name FROM categories ORDER BY name");
                    while ($cat = $categories->fetch_assoc()) {
                        $selected = ($cat['id'] == $category_id) ? 'selected' : '';
                        echo "<option value='{$cat['id']}' {$selected}>" . htmlspecialchars($cat['name']) . "</option>";
                    }
                    ?>
                </select>
            </div>
             <div>
                <label for="supplier_id" class="block text-sm font-medium text-gray-700">Supplier</label>
                <select name="supplier_id" id="supplier_id" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="">Pilih Supplier</option>
                    <?php
                    $suppliers = $mysqli->query("SELECT id, name FROM suppliers WHERE status = 'active' ORDER BY name");
                    while ($sup = $suppliers->fetch_assoc()) {
                        $selected = ($sup['id'] == $supplier_id) ? 'selected' : '';
                        echo "<option value='{$sup['id']}' {$selected}>" . htmlspecialchars($sup['name']) . "</option>";
                    }
                    ?>
                </select>
            </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mt-6">
            <div>
                <label for="unit_price" class="block text-sm font-medium text-gray-700">Harga Satuan</label>
                <input type="number" step="0.01" name="unit_price" id="unit_price" value="<?php echo $unit_price; ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
             <div>
                <label for="minimum_stock" class="block text-sm font-medium text-gray-700">Stok Minimum</label>
                <input type="number" name="minimum_stock" id="minimum_stock" value="<?php echo $minimum_stock; ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
             <div>
                <label for="weight" class="block text-sm font-medium text-gray-700">Berat (kg)</label>
                <input type="number" step="0.01" name="weight" id="weight" value="<?php echo $weight; ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>
        
        <div class="mt-6">
            <label for="status" class="block text-sm font-medium text-gray-700">Status Produk</label>
            <select name="status" id="status" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                <option value="active" <?php echo ($status == 'active') ? 'selected' : ''; ?>>Aktif</option>
                <option value="inactive" <?php echo ($status == 'inactive') ? 'selected' : ''; ?>>Tidak Aktif</option>
                <option value="discontinued" <?php echo ($status == 'discontinued') ? 'selected' : ''; ?>>Diskంటిnu</option>
            </select>
        </div>

        <div class="mt-8 flex justify-end">
            <?php if ($update) : ?>
                <button type="submit" name="update" class="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-save-fill mr-2"></i> Simpan Perubahan</button>
            <?php else : ?>
                <button type="submit" name="save" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-plus-circle-fill mr-2"></i> Tambah Produk</button>
            <?php endif; ?>
        </div>
    </form>
</div>

<?php include 'includes/footer.php'; ?>