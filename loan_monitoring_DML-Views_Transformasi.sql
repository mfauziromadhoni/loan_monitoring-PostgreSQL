--####### VIEWS: LAPISAN TRANSFORMASI #######--

--### View Profil Kredit Debitur ###--
CREATE OR REPLACE VIEW kredit.v_profil_kredit_debitur AS
SELECT
	d.cif,
	d.nama_debitur,
	d.jenis_kelamin,
	DATE_PART('year', AGE(d.tanggal_lahir))::INT		AS umur,
	d.pekerjaan,
	d.segmen_debitur,
	d.kota,
	d.penghasilan_bulanan,
	d.tanggal_bergabung,
	--berapa lama menjadi nasabah
	DATE_PART('year', AGE(tanggal_bergabung))::INT		AS lama_bergabung_tahun,
	--jumlah fasilitas kredit
	COUNT(f.id_fasilitas)								AS jumlah_fasilitas,
	--total plafon kredit
	SUM(f.plafon)										AS total_plafon,
	--total outstanding
	SUM(f.outstanding)									AS total_outstanding,
	--kolektibilitas terburuk (yang paling beresiko)
	MAX(f.kolektibilitas_kode)							AS kolektibilitas_terburuk,
	-- Rasio kredit terhadap penghasilan (DBR — Debt Burden Ratio)
	ROUND(
		SUM(f.plafon)::NUMERIC / NULLIF(d.penghasilan_bulanan * 12, 0) * 100,
		2
	)													AS dbr_pct
FROM kredit.debitur d
LEFT JOIN kredit.fasilitas_kredit f ON d.cif = f.cif
GROUP BY 
	d.cif, d.nama_debitur, d.jenis_kelamin, d.tanggal_lahir,
    d.pekerjaan, d.segmen_debitur, d.kota,
    d.penghasilan_bulanan, d.tanggal_bergabung;



--### View Kualitas Portofolio Kredit ###--
CREATE OR REPLACE VIEW kredit.v_kualitas_portofolio AS
SELECT
	f.segmen_kredit,
	f.produk_kredit,
	f.kolektibilitas_kode,
	f.kolektibilitas_label,
	--Jumlah Rekening per kategori
	COUNT(f.id_fasilitas)							AS jumlah_rekening,
	--Total outstanding per kategori
	SUM(f.outstanding)								AS total_outstanding,
	--Persentase dari total outstanding
	ROUND(
		SUM(f.outstanding) * 100.0 /
		SUM(SUM(f.outstanding)) OVER (PARTITION BY f.segmen_kredit), 2
	)												AS pct_outstanding_segmen,
	--Total nilai agunan
	SUM(f.nilai_agunan)								AS total_agunan,
	--Coverage ratio agunan terhadap outstanding
	ROUND(
		SUM(f.nilai_agunan::NUMERIC) /
		NULLIF(SUM(f.outstanding), 0) * 100, 2
	)												AS coverage_ratio_pct,
	--Rata rata hari tunggakan
	ROUND(
		AVG(f.hari_tunggakan), 1
	)												AS avg_hari_tunggakan
FROM kredit.fasilitas_kredit f
WHERE f.status_kredit = 'Aktif'
GROUP BY 
	f.segmen_kredit, f.produk_kredit,
	f.kolektibilitas_kode, f.kolektibilitas_label
ORDER BY
	f.segmen_kredit, f.kolektibilitas_kode;


--### View Histori Pembayaran per Fasilitas ###--
CREATE OR REPLACE VIEW kredit.v_histori_pembayaran AS
SELECT
	p.id_fasilitas,
	p.ke_angsuran,
	p.tanggal_jatuh_tempo_angsuran,
	p.tanggal_bayar,
	p.total_angsuran,
	p.nominal_bayar,
	p.status_pembayaran,
	p.denda,
	--Selisih hari antara tanggal bayar dan jatuh tempo
	CASE
		WHEN p.tanggal_bayar IS NOT NULL
		THEN (p.tanggal_bayar - tanggal_jatuh_tempo_angsuran)
		ELSE NULL
	END															AS selisih_hari,
	--Sisa kewajiban yang belum dibayar
	GREATEST(0, p.total_angsuran - p.nominal_bayar)			AS kekurangan_bayar,
	--Running total pembayaran per fasilitas
	SUM(p.nominal_bayar) OVER(
		PARTITION BY p.id_fasilitas
		ORDER BY(p.ke_angsuran)
	)															AS kumulatif_bayar
FROM kredit.pembayaran p
ORDER BY p.id_fasilitas, p.ke_angsuran;