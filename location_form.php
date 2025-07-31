<?php
include 'includes/header.php';

// Inisialisasi variabel
$id = 0;
$location_code = '';
$location_name = '';
$zone = '';
$capacity = 0;
$temperature_controlled = 0;
$status = 'active';
$update = false;

// Mode edit
if (isset($_GET['id'])) {
    $id = $_GET['id'];
    $update = true;
    $result = $mysqli->query("SELECT * FROM warehouse_locations WHERE id=$id") or die($mysqli->error);
    if ($result->num_rows == 1) {
        $row = $result->fetch_assoc();
        extract($row);
    }
}
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700"><?php echo $update ? '✏️ Edit Lokasi Gudang' : '✨ Tambah Lokasi Baru'; ?></h1>
    <a href="locations.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali
    </a>
</div>

<div class="bg-white shadow-md rounded-lg p-6">
    <form action="location_action.php" method="POST">
        <input type="hidden" name="id" value="<?php echo $id; ?>">
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
                <label for="location_code" class="block text-sm font-medium text-gray-700">Kode Lokasi (e.g., A-01-01)</label>
                <input type="text" name="location_code" id="location_code" value="<?php echo htmlspecialchars($location_code); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="location_name" class="block text-sm font-medium text-gray-700">Nama Lokasi</label>
                <input type="text" name="location_name" id="location_name" value="<?php echo htmlspecialchars($location_name); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="zone" class="block text-sm font-medium text-gray-700">Zona</label>
                <input type="text" name="zone" id="zone" value="<?php echo htmlspecialchars($zone); ?>" class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
            <div>
                <label for="capacity" class="block text-sm font-medium text-gray-700">Kapasitas (Unit)</label>
                <input type="number" name="capacity" id="capacity" value="<?php echo $capacity; ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-6">
            <div>
                <label for="status" class="block text-sm font-medium text-gray-700">Status Lokasi</label>
                <select name="status" id="status" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="active" <?php echo ($status == 'active') ? 'selected' : ''; ?>>Aktif</option>
                    <option value="maintenance" <?php echo ($status == 'maintenance') ? 'selected' : ''; ?>>Dalam Perbaikan</option>
                    <option value="inactive" <?php echo ($status == 'inactive') ? 'selected' : ''; ?>>Tidak Aktif</option>
                </select>
            </div>
            <div class="flex items-end pb-1">
                <div class="flex items-center">
                    <input id="temperature_controlled" name="temperature_controlled" type="checkbox" value="1" <?php echo ($temperature_controlled) ? 'checked' : ''; ?> class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded">
                    <label for="temperature_controlled" class="ml-2 block text-sm text-gray-900">Suhu Terkontrol (AC/Pendingin)</label>
                </div>
            </div>
        </div>

        <div class="mt-8 flex justify-end">
            <?php if ($update) : ?>
                <button type="submit" name="update" class="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-save-fill mr-2"></i> Simpan</button>
            <?php else : ?>
                <button type="submit" name="save" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300"><i class="bi bi-plus-circle-fill mr-2"></i> Tambah Lokasi</button>
            <?php endif; ?>
        </div>
    </form>
</div>

<?php include 'includes/footer.php'; ?>