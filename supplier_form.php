<?php
include 'includes/header.php';

// Inisialisasi variabel untuk form
$id = 0;
$name = '';
$contact_person = '';
$phone = '';
$email = '';
$address = '';
$city = '';
$postal_code = '';
$status = 'active';
$update = false;

// Jika mode edit, ambil data dari database
if (isset($_GET['id'])) {
    $id = $_GET['id'];
    $update = true;
    $result = $mysqli->query("SELECT * FROM suppliers WHERE id=$id") or die($mysqli->error);
    if ($result->num_rows == 1) {
        $row = $result->fetch_assoc();
        extract($row); // Fungsi extract() akan membuat variabel dari array, misal $row['name'] menjadi $name
    }
}
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700"><?php echo $update ? '✏️ Edit Supplier' : '✨ Tambah Supplier Baru'; ?></h1>
    <a href="suppliers.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali
    </a>
</div>

<div class="bg-white shadow-md rounded-lg p-6">
    <form action="supplier_action.php" method="POST">
        <input type="hidden" name="id" value="<?php echo $id; ?>">

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
                <label for="name" class="block text-sm font-medium text-gray-700">Nama Supplier</label>
                <input type="text" name="name" id="name" value="<?php echo htmlspecialchars($name); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="contact_person" class="block text-sm font-medium text-gray-700">Kontak Person</label>
                <input type="text" name="contact_person" id="contact_person" value="<?php echo htmlspecialchars($contact_person); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="phone" class="block text-sm font-medium text-gray-700">Telepon</label>
                <input type="text" name="phone" id="phone" value="<?php echo htmlspecialchars($phone); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
                <input type="email" name="email" id="email" value="<?php echo htmlspecialchars($email); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>

        <div class="mt-6">
            <label for="address" class="block text-sm font-medium text-gray-700">Alamat</label>
            <textarea name="address" id="address" rows="3" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500"><?php echo htmlspecialchars($address); ?></textarea>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-6">
            <div>
                <label for="city" class="block text-sm font-medium text-gray-700">Kota</label>
                <input type="text" name="city" id="city" value="<?php echo htmlspecialchars($city); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="postal_code" class="block text-sm font-medium text-gray-700">Kode Pos</label>
                <input type="text" name="postal_code" id="postal_code" value="<?php echo htmlspecialchars($postal_code); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>

        <div class="mt-6">
            <label for="status" class="block text-sm font-medium text-gray-700">Status</label>
            <select name="status" id="status" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                <option value="active" <?php echo ($status == 'active') ? 'selected' : ''; ?>>Aktif</option>
                <option value="inactive" <?php echo ($status == 'inactive') ? 'selected' : ''; ?>>Tidak Aktif</option>
            </select>
        </div>

        <div class="mt-8 flex justify-end">
            <?php if ($update) : ?>
                <button type="submit" name="update" class="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-save-fill mr-2"></i> Simpan Perubahan</button>
            <?php else : ?>
                <button type="submit" name="save" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-plus-circle-fill mr-2"></i> Tambah Supplier</button>
            <?php endif; ?>
        </div>
    </form>
</div>

<?php include 'includes/footer.php'; ?>