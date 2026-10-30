-- View ini yang akan dikoneksikan ke Power BI
-- masing-masing menjadi satu tabel di Power BI

-- 1. Untuk halaman Overview & NPL
CREATE OR REPLACE VIEW kredit.vw_pbi_npl_summary AS
SELECT
    f.segmen_kredit,
    f.produk_kredit,
    f.kolektibilitas_kode,
    f.kolektibilitas_label,
    d.kota,
    d.pekerjaan,
    f.status_kredit,
    f.jenis_agunan,
    COUNT(f.id_fasilitas)                               AS jumlah_rekening,
    SUM(f.plafon)                                       AS total_plafon,
    SUM(f.outstanding)                                  AS total_outstanding,
    SUM(f.nilai_agunan)                                 AS total_agunan,
    SUM(f.hari_tunggakan)                               AS total_hari_tunggakan,
    AVG(f.suku_bunga)                                   AS avg_suku_bunga
FROM kredit.fasilitas_kredit f
JOIN kredit.debitur d ON f.cif = d.cif
GROUP BY
    f.segmen_kredit, f.produk_kredit,
    f.kolektibilitas_kode, f.kolektibilitas_label,
    d.kota, d.pekerjaan, f.status_kredit, f.jenis_agunan;

-- 2. Untuk halaman Tren Pembayaran
CREATE OR REPLACE VIEW kredit.vw_pbi_pembayaran_trend AS
SELECT
    DATE_TRUNC('month', p.tanggal_jatuh_tempo_angsuran) AS bulan,
    TO_CHAR(DATE_TRUNC('month',
        p.tanggal_jatuh_tempo_angsuran), 'YYYY-MM')    AS bulan_label,
    f.segmen_kredit,
    f.produk_kredit,
    p.status_pembayaran,
    COUNT(p.id_pembayaran)                              AS jumlah_transaksi,
    SUM(p.total_angsuran)                               AS total_tagihan,
    SUM(p.nominal_bayar)                                AS total_terealisasi,
    SUM(p.denda)                                        AS total_denda
FROM kredit.pembayaran p
JOIN kredit.fasilitas_kredit f ON p.id_fasilitas = f.id_fasilitas
GROUP BY
    DATE_TRUNC('month', p.tanggal_jatuh_tempo_angsuran),
    TO_CHAR(DATE_TRUNC('month',
        p.tanggal_jatuh_tempo_angsuran), 'YYYY-MM'),
    f.segmen_kredit, f.produk_kredit, p.status_pembayaran;

-- 3. Untuk halaman Watch List
CREATE OR REPLACE VIEW kredit.vw_pbi_watchlist AS
SELECT
    d.cif,
    d.nama_debitur,
    d.kota,
    d.segmen_debitur,
    d.penghasilan_bulanan,
    f.id_fasilitas,
    f.produk_kredit,
    f.plafon,
    f.outstanding,
    f.kolektibilitas_kode,
    f.kolektibilitas_label,
    f.hari_tunggakan,
    f.jenis_agunan,
    f.nilai_agunan,
    CASE
        WHEN f.kolektibilitas_kode >= 4 THEN 'Segera'
        WHEN f.kolektibilitas_kode = 3  THEN 'Tinggi'
        WHEN f.kolektibilitas_kode = 2  THEN 'Sedang'
        ELSE 'Pantau'
    END                                                 AS prioritas
FROM kredit.fasilitas_kredit f
JOIN kredit.debitur d ON f.cif = d.cif
WHERE f.status_kredit = 'Aktif'
  AND f.kolektibilitas_kode >= 2;