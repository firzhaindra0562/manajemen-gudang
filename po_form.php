<?php
include 'includes/header.php';

// Ambil data supplier untuk dropdown
$suppliers = $mysqli->query("SELECT id, name FROM suppliers WHERE status = 'active' ORDER BY name ASC");

// Ambil data produk untuk dropdown, termasuk harga sebagai biaya default
$products = $mysqli->query("SELECT id, name, sku, unit_price FROM products WHERE status = 'active' ORDER BY name ASC");
$product_options = [];
while ($p = $products->fetch_assoc()) {
    $product_options[] = $p;
}
?>

<div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-gray-700">Buat Purchase Order (PO) Baru</h1>
    <a href="purchase_orders.php" class="bg-gray-500 hover:bg-gray-600 text-white font-bold py-2 px-4 rounded-lg flex items-center transition duration-300">
        <i class="bi bi-arrow-left-circle mr-2"></i> Kembali
    </a>
</div>

<form id="poForm" action="po_action.php" method="POST">
    <div class="bg-white shadow-md rounded-lg p-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
            <div>
                <label for="supplier_id" class="block text-sm font-medium text-gray-700">Supplier</label>
                <select id="supplier_id" name="supplier_id" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
                    <option value="">-- Pilih Supplier --</option>
                    <?php while ($supplier = $suppliers->fetch_assoc()): ?>
                        <option value="<?php echo $supplier['id']; ?>"><?php echo htmlspecialchars($supplier['name']); ?></option>
                    <?php endwhile; ?>
                </select>
            </div>
            <div>
                <label for="po_number" class="block text-sm font-medium text-gray-700">Nomor PO</label>
                <input type="text" id="po_number" name="po_number" value="PO-<?php echo time(); ?>" required class="mt-1 block w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md shadow-sm" readonly>
            </div>
            <div>
                <label for="expected_delivery" class="block text-sm font-medium text-gray-700">Tanggal Harapan Tiba</label>
                <input type="date" id="expected_delivery" name="expected_delivery" value="<?php echo date('Y-m-d', strtotime('+7 days')); ?>" required class="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500">
            </div>
        </div>

        <div class="overflow-x-auto mt-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">Detail Produk</h3>
            <table class="min-w-full">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-2/5">Produk</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-1/5">Biaya Satuan</th>
                        <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase w-1/5">Jumlah Dipesan</th>
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
                        <td colspan="3" class="px-4 py-2 text-right text-lg font-bold text-gray-900">TOTAL</td>
                        <td colspan="2" id="po_total" class="px-4 py-2 text-left text-lg font-bold text-gray-900">Rp 0</td>
                    </tr>
                </tfoot>
            </table>
        </div>
        
        <div class="mt-8 flex justify-end">
            <button type="submit" name="save_po" class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-6 rounded-lg flex items-center transition duration-300">
                <i class="bi bi-save-fill mr-2"></i> Simpan PO
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
                    <option value="<?php echo $p['id']; ?>" data-cost="<?php echo $p['unit_price']; ?>">
                        <?php echo htmlspecialchars($p['name']) . ' (' . htmlspecialchars($p['sku']) . ')'; ?>
                    </option>
                <?php endforeach; ?>
            </select>
        </td>
        <td class="px-4 py-2">
            <input type="number" step="0.01" name="products[__INDEX__][unit_cost]" class="unit-cost-input mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm" value="0" required>
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

    addProductBtn.addEventListener('click', function () {
        const templateContent = productRowTemplate.innerHTML.replace(/__INDEX__/g, rowIndex);
        const newRow = document.createElement('tr');
        newRow.innerHTML = templateContent;
        productItemsTbody.appendChild(newRow);
        
        // Auto-fill a new row's cost when a product is selected
        const newProductSelect = newRow.querySelector('.product-select');
        newProductSelect.addEventListener('change', function() {
            const selectedOption = this.options[this.selectedIndex];
            const unitCost = parseFloat(selectedOption.dataset.cost) || 0;
            const row = this.closest('tr');
            row.querySelector('.unit-cost-input').value = unitCost;
            updateTotals(); // Trigger a total update
        });

        rowIndex++;
    });

    productItemsTbody.addEventListener('click', function (e) {
        if (e.target.closest('.remove-row-btn')) {
            e.target.closest('tr').remove();
            updateTotals();
        }
    });

    productItemsTbody.addEventListener('input', function (e) {
        if (e.target.matches('.unit-cost-input, .quantity-input')) {
            const row = e.target.closest('tr');
            const unitCost = parseFloat(row.querySelector('.unit-cost-input').value) || 0;
            const quantity = parseInt(row.querySelector('.quantity-input').value) || 0;
            
            row.querySelector('.line-total').textContent = formatRupiah(unitCost * quantity);
            updateTotals();
        }
    });

    function updateTotals() {
        let total = 0;
        document.querySelectorAll('#product_items tr').forEach(row => {
            const unitCost = parseFloat(row.querySelector('.unit-cost-input').value) || 0;
            const quantity = parseInt(row.querySelector('.quantity-input').value) || 0;
            total += unitCost * quantity;
        });

        document.getElementById('po_total').textContent = formatRupiah(total);
    }
    
    function formatRupiah(number) {
        return 'Rp ' + new Intl.NumberFormat('id-ID').format(number);
    }
});
</script>