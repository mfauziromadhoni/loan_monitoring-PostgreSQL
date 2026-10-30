-- ###### AUDIT UNCLEANED DATA AT STAGING ######--

-- ### AUDIT DEBITUR ### --
--Cek NIK kosong
SELECT COUNT(*) AS nik_kosong
FROM kredit.stg_debitur
WHERE nik IS NULL OR TRIM(nik) = '';	--nik_kosong = 11

--Cek NPWP kosong
SELECT COUNT(*) AS npwp_kosong
FROM kredit.stg_debitur
WHERE npwp IS NULL OR TRIM(npwp) = '';	--npwp_kosong = 11

--Cek Penghasilan Invalid
SELECT COUNT(*) AS penghasilan_invalid
FROM kredit.stg_debitur
WHERE penghasilan_bulanan::BIGINT <= 0; --penghasilan_invalid = 0

--Cek distribusi segmen
SELECT
	segmen_debitur,
	COUNT(*) AS jumlah
FROM kredit.stg_debitur
GROUP BY segmen_debitur
ORDER BY jumlah DESC; --Konsumer = 87, Menengah = 79, Kecil = 69, Mikro = 65


-- ### AUDIT FASILITAS KREDIT ### --
--Cek suku bunga nol (tidak wajar)
SELECT COUNT(*) AS suku_bunga_nol
FROM kredit.stg_fasilitas_kredit
WHERE suku_bunga::NUMERIC = 0; --suku_bunga_nol = 6

--Cek outstanding negatif
SELECT COUNT(*) AS outstanding_negatif
FROM kredit.stg_fasilitas_kredit
WHERE outstanding :: BIGINT < 0; --outstanding_negatif = 5

--Cek distribusi kolektibilitas
SELECT
	kolektibilitas_kode,
	kolektibilitas_label,
	COUNT(*) AS jumlah,
	ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM kredit.stg_fasilitas_kredit
GROUP BY kolektibilitas_kode, kolektibilitas_label
ORDER  BY kolektibilitas_kode;


-- ### AUDIT PEMBAYARAN ### --
--Cek nominal bayar negatif
SELECT COUNT(*) AS nominal_negatif
FROM kredit.stg_pembayaran
WHERE TRIM(nominal_bayar) != ''
	AND nominal_bayar IS NOT NULL
	AND ROUND(nominal_bayar::NUMERIC) < 0; -- nominal_negatif = 185

--Cek nominal bayar kosong
SELECT COUNT(*) AS nominal_kosong
FROM kredit.stg_pembayaran
WHERE nominal_bayar IS NULL 
	OR TRIM(nominal_bayar::TEXT) = ''; --nominal_kosong = 141

--Cek distribusi status_pembayaran
SELECT
	status_pembayaran,
	COUNT(*) AS jumlah
FROM kredit.stg_pembayaran
GROUP BY status_pembayaran
ORDER BY jumlah DESC;


-- ###### INSERT CLEANED DATA INTO PRODUCTION ######--

-- ### INSERT DEBITUR ### --
INSERT INTO kredit.debitur(
	cif, nama_debitur, jenis_kelamin, tanggal_lahir,
    nik, npwp, pekerjaan, segmen_debitur, kota,
    penghasilan_bulanan, tanggal_bergabung
)
SELECT
	TRIM(cif),
	INITCAP(TRIM(nama_debitur)),
	UPPER(TRIM(jenis_kelamin)),
	tanggal_lahir::DATE,
	--nik kosong diganti NULL
	CASE WHEN TRIM(nik) = '' THEN NULL ELSE TRIM(nik) END,
	--npwp kosong diganti NULL
	CASE WHEN TRIM(npwp) = '' THEN NULL ELSE TRIM(npwp) END,
	TRIM(pekerjaan),
	TRIM(segmen_debitur),
	TRIM(kota),
	penghasilan_bulanan::BIGINT,
	tanggal_bergabung::DATE
FROM kredit.stg_debitur
WHERE 
	--hapus baris tanpa CIF
	TRIM(cif) != ''
	--hapus penghasilan_bulanan invalid
	AND penghasilan_bulanan::BIGINT > 0
ON CONFLICT(cif) DO NOTHING;


-- ### INSERT FASILITAS KREDIT ### --
INSERT INTO kredit.fasilitas_kredit (
    id_fasilitas, cif, produk_kredit, segmen_kredit,
    tanggal_realisasi, tanggal_jatuh_tempo, tenor_bulan,
    plafon, suku_bunga, outstanding,
    kolektibilitas_kode, kolektibilitas_label, hari_tunggakan,
    jenis_agunan, nilai_agunan, status_kredit
)
SELECT
	TRIM(id_fasilitas),
	TRIM(cif),
	TRIM(produk_kredit),
	TRIM(segmen_kredit),
	tanggal_realisasi::DATE,
	tanggal_jatuh_tempo::DATE,
	tenor_bulan::INT,
	plafon::BIGINT,
	--suku bunga 0 diganti dengan rata rata segmen (default 9%)
	CASE WHEN suku_bunga::NUMERIC = 0 THEN 9.00 ELSE suku_bunga::NUMERIC END,
	--Outstanding diambil nilai absolutnya
	ABS(outstanding::BIGINT),
	kolektibilitas_kode::INT,
	TRIM(kolektibilitas_label),
	hari_tunggakan::INT,
	TRIM(jenis_agunan),
	nilai_agunan::BIGINT,
	TRIM(status_kredit)
FROM kredit.stg_fasilitas_kredit
WHERE
	id_fasilitas != ''
	AND TRIM(cif) IN (SELECT cif FROM kredit.debitur)
	AND plafon::BIGINT > 0
	AND kolektibilitas_kode::INT BETWEEN 1 AND 5
ON CONFLICT (id_fasilitas) DO NOTHING;


-- ### INSERT PEMBAYARAN ### --
INSERT INTO kredit.pembayaran (
    id_pembayaran, id_fasilitas,
    tanggal_jatuh_tempo_angsuran, tanggal_bayar,
    angsuran_pokok, angsuran_bunga, total_angsuran,
    nominal_bayar, status_pembayaran, denda, ke_angsuran
)
SELECT
	TRIM(id_pembayaran),
	TRIM(id_fasilitas),
	tanggal_jatuh_tempo_angsuran::DATE,
	--tanggal bayar kosong dijadikan NULL
	CASE WHEN TRIM(tanggal_bayar) = '' THEN NULL ELSE tanggal_bayar::DATE END,
	ABS(ROUND(angsuran_pokok::NUMERIC)::BIGINT),
	ABS(ROUND(angsuran_bunga::NUMERIC)::BIGINT),
	ABS(ROUND(total_angsuran::NUMERIC)::BIGINT),
	--nominal bayar negatif atau kosong dijadikan NULL
	CASE WHEN TRIM(nominal_bayar::TEXT) = '' THEN 0
		 WHEN nominal_bayar IS NULL THEN 0
		 WHEN ROUND(nominal_bayar::NUMERIC) < 0 THEN 0
		 ELSE ROUND(nominal_bayar::NUMERIC)::BIGINT END,
	TRIM(status_pembayaran),
	COALESCE(ROUND(denda::NUMERIC)::BIGINT, 0),
	ke_angsuran::INT
FROM kredit.stg_pembayaran
WHERE
	id_pembayaran != ''
	AND TRIM(id_fasilitas) IN (SELECT id_fasilitas FROM kredit.fasilitas_kredit)
	AND TRIM(status_pembayaran) IN ('Tepat Waktu', 'Terlambat', 'Tidak Bayar')
ON CONFLICT (id_pembayaran) DO NOTHING;

--Cek Insert Table Production
SELECT 'debitur'          AS tabel, COUNT(*) AS total FROM kredit.debitur
UNION ALL
SELECT 'fasilitas_kredit' AS tabel, COUNT(*) AS total FROM kredit.fasilitas_kredit
UNION ALL
SELECT 'pembayaran'       AS tabel, COUNT(*) AS total FROM kredit.pembayaran;

