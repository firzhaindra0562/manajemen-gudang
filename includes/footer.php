</main>
    <footer class="bg-light text-center text-lg-start mt-5">
        <div class="text-center p-3" style="background-color: rgba(0, 0, 0, 0.05);">
            © <?php echo date("Y"); ?> Manajemen Gudang - Dibuat dengan ❤️
        </div>
    </footer>
    
    <script>
        document.addEventListener('DOMContentLoaded', function () {
            const masterDataBtn = document.getElementById('masterDataBtn');
            const masterDataMenu = document.getElementById('masterDataMenu');

            // Toggle menu saat tombol diklik
            masterDataBtn.addEventListener('click', function (event) {
                event.stopPropagation(); // Mencegah event 'click' menyebar ke window
                masterDataMenu.classList.toggle('hidden');
            });

            // Sembunyikan menu saat mengklik di luar area menu
            window.addEventListener('click', function (event) {
                if (!masterDataMenu.contains(event.target) && !masterDataBtn.contains(event.target)) {
                    masterDataMenu.classList.add('hidden');
                }
            });
        });
    </script>
    </body>
</html>
<?php
// Tutup koneksi database jika ada
if (isset($mysqli)) {
    $mysqli->close();
}
?>