<?php
include 'includes/header.php';

// Ambil data pelanggan untuk dropdown
$customers = $mysqli->query("SELECT id, name FROM customers WHERE status = 'active' ORDER BY name ASC");

// Ambil data produk untuk dropdown
// Kita juga ambil harga untuk perhitungan di JavaScript
$products = $mysqli->query("SELECT id, name, sku, unit_price FROM products WHERE status = 'active' ORDER BY name ASC");
$product_options = [];
while ($p = $products->fetch_assoc()) {
    $product_options[] = $p;
}
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">Buat Pesanan Baru</h1>
    <a href="orders.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali
    </a>
</div>

<form id="orderForm" action="order_action.php" method="POST">
    <div class="bg-white shadow-md rounded-lg p-6">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div>
                <label for="customer_id" class="block text-sm font-medium text-gray-700">Pelanggan</label>
                <select id="customer_id" name="customer_id" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="">-- Pilih Pelanggan --</option>
                    <?php while ($customer = $customers->fetch_assoc()): ?>
                        <option value="<?php echo $customer['id']; ?>"><?php echo htmlspecialchars($customer['name']); ?></option>
                    <?php endwhile; ?>
                </select>
            </div>
            <div>
                <label for="order_number" class="block text-sm font-medium text-gray-700">Nomor Order</label>
                <input type="text" id="order_number" name="order_number" value="ORD-<?php echo time(); ?>" required class="mt-1 block w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md shadow-sm" readonly>
            </div>
        </div>

        <div class="overflow-x-auto mt-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Detail Produk</h3>
            <table class="min-w-full">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-2/5">Produk</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-1/5">Harga Satuan</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-1/5">Jumlah</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-1/5">Subtotal</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Aksi</th>
                    </tr>
                </thead>
                <tbody id="product_items" class="divide-y divide-gray-200">
                    </tbody>
                <tfoot class="bg-gray-50">
                    <tr>
                        <td colspan="5" class="p-2">
                            <button type="button" id="add_product_btn" class="bg-green-500 hover:bg-green-600 text-white text-sm font-bold py-1 px-3 rounded-lg flex items-center">
                                <i class="bi bi-plus-circle mr-1"></i> Tambah Produk
                            </button>
                        </td>
                    </tr>
                    <tr>
                        <td colspan="3" class="px-4 py-2 text-right font-semibold text-gray-700">Subtotal</td>
                        <td colspan="2" id="order_subtotal" class="px-4 py-2 text-left font-semibold text-gray-800">Rp 0</td>
                    </tr>
                     <tr>
                        <td colspan="3" class="px-4 py-2 text-right font-semibold text-gray-700">Pajak (10%)</td>
                        <td colspan="2" id="order_tax" class="px-4 py-2 text-left font-semibold text-gray-800">Rp 0</td>
                    </tr>
                     <tr>
                        <td colspan="3" class="px-4 py-2 text-right text-lg font-bold text-gray-900">TOTAL</td>
                        <td colspan="2" id="order_total" class="px-4 py-2 text-left text-lg font-bold text-gray-900">Rp 0</td>
                    </tr>
                </tfoot>
            </table>
        </div>
        
        <div class="mt-8 flex justify-end">
            <button type="submit" name="save_order" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-6 rounded-lg flex items-center transition duration-300">
                <i class="bi bi-save-fill mr-2"></i> Simpan Pesanan
            </button>
        </div>
    </div>
</form>

<template id="product_row_template">
    <tr class="product-row">
        <td class="px-4 py-2">
            <select name="products[__INDEX__][id]" class="product-select mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm" required>
                <option value="">-- Pilih Produk --</option>
                <?php foreach ($product_options as $p): ?>
                    <option value="<?php echo $p['id']; ?>" data-price="<?php echo $p['unit_price']; ?>">
                        <?php echo htmlspecialchars($p['name']) . ' (' . htmlspecialchars($p['sku']) . ')'; ?>
                    </option>
                <?php endforeach; ?>
            </select>
        </td>
        <td class="px-4 py-2">
            <span class="unit-price text-gray-600">Rp 0</span>
            <input type="hidden" name="products[__INDEX__][unit_price]" class="unit-price-input">
        </td>
        <td class="px-4 py-2">
            <input type="number" name="products[__INDEX__][quantity]" class="quantity-input mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm" value="1" min="1" required>
        </td>
        <td class="px-4 py-2">
            <span class="line-total font-semibold text-gray-800">Rp 0</span>
        </td>
        <td class="px-4 py-2">
            <button type="button" class="remove-row-btn text-red-500 hover:text-red-700">
                <i class="bi bi-trash-fill"></i>
            </button>
        </td>
    </tr>
</template>

<?php include 'includes/footer.php'; ?>

<script>
document.addEventListener('DOMContentLoaded', function () {
    const addProductBtn = document.getElementById('add_product_btn');
    const productItemsTbody = document.getElementById('product_items');
    const productRowTemplate = document.getElementById('product_row_template');
    let rowIndex = 0;

    // Fungsi untuk menambah baris produk baru
    addProductBtn.addEventListener('click', function () {
        const templateContent = productRowTemplate.innerHTML.replace(/__INDEX__/g, rowIndex);
        const newRow = document.createElement('tr');
        newRow.innerHTML = templateContent;
        productItemsTbody.appendChild(newRow);
        rowIndex++;
    });

    // Fungsi untuk menghapus baris dan update total
    productItemsTbody.addEventListener('click', function (e) {
        if (e.target.closest('.remove-row-btn')) {
            e.target.closest('tr').remove();
            updateTotals();
        }
    });

    // Fungsi untuk update harga dan total saat ada perubahan
    productItemsTbody.addEventListener('input', function (e) {
        if (e.target.matches('.product-select, .quantity-input')) {
            const row = e.target.closest('tr');
            const productSelect = row.querySelector('.product-select');
            const quantityInput = row.querySelector('.quantity-input');
            const selectedOption = productSelect.options[productSelect.selectedIndex];
            
            const unitPrice = parseFloat(selectedOption.dataset.price) || 0;
            const quantity = parseInt(quantityInput.value) || 0;

            row.querySelector('.unit-price').textContent = formatRupiah(unitPrice);
            row.querySelector('.unit-price-input').value = unitPrice;
            row.querySelector('.line-total').textContent = formatRupiah(unitPrice * quantity);
            
            updateTotals();
        }
    });

    // Fungsi utama untuk menghitung semua total
    function updateTotals() {
        let subtotal = 0;
        document.querySelectorAll('#product_items tr').forEach(row => {
            const unitPrice = parseFloat(row.querySelector('.unit-price-input').value) || 0;
            const quantity = parseInt(row.querySelector('.quantity-input').value) || 0;
            subtotal += unitPrice * quantity;
        });

        const tax = subtotal * 0.10; // Pajak 10%
        const total = subtotal + tax;

        document.getElementById('order_subtotal').textContent = formatRupiah(subtotal);
        document.getElementById('order_tax').textContent = formatRupiah(tax);
        document.getElementById('order_total').textContent = formatRupiah(total);
    }
    
    // Helper untuk format Rupiah
    function formatRupiah(number) {
        return 'Rp ' + new Intl.NumberFormat('id-ID').format(number);
    }
});
</script>