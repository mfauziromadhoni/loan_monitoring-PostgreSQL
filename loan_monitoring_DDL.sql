--######DDL (Data Definition Language)#######--

--Staging Debitur
CREATE TABLE IF NOT EXISTS kredit.stg_debitur(
	cif 				TEXT,
	nama_debitur		TEXT,
	jenis_kelamin		TEXT,
	tanggal_lahir		TEXT,
	nik					TEXT,
	npwp				TEXT,
	pekerjaan			TEXT,
	segmen_debitur		TEXT,
	kota				TEXT,
	penghasilan_bulanan	TEXT,
	tanggal_bergabung	TEXT
);

--Staging Fasilitas Kredit
CREATE TABLE IF NOT EXISTS kredit.stg_fasilitas_kredit(
	id_fasilitas			TEXT,
	cif						TEXT,
	produk_kredit			TEXT,
	segmen_kredit			TEXT,
	tanggal_realisasi		TEXT,
	tanggal_jatuh_tempo		TEXT,
	tenor_bulan				TEXT,
	plafon					TEXT,
	suku_bunga				TEXT,
	outstanding				TEXT,
	kolektibilitas_kode		TEXT,
	kolektibilitas_label	TEXT,
	hari_tunggakan			TEXT,
	jenis_agunan			TEXT,
	nilai_agunan			TEXT,
	status_kredit			TEXT
);

--Staging Pembayaran
CREATE TABLE IF NOT EXISTS kredit.stg_pembayaran(
	id_pembayaran					TEXT,
	id_fasilitas					TEXT,
	tanggal_jatuh_tempo_angsuran	TEXT,
	tanggal_bayar					TEXT,
	angsuran_pokok					TEXT,
	angsuran_bunga					TEXT,
	total_angsuran					TEXT,
	nominal_bayar					TEXT,
	status_pembayaran				TEXT,
	denda							TEXT,
	ke_angsuran						TEXT
);


--Validasi Import Tabel
SELECT COUNT(*) FROM kredit.stg_debitur;
SELECT COUNT(*) FROM kredit.stg_fasilitas_kredit;
SELECT COUNT(*) FROM kredit.stg_pembayaran;


--#### TABLE PRODUCTION #### --

-- PRODUCTION : debitur
CREATE TABLE IF NOT EXISTS kredit.debitur(
	cif					VARCHAR(20)			PRIMARY KEY,
	nama_debitur		VARCHAR(100)		NOT NULL,
	jenis_kelamin		CHAR(1)				CHECK(jenis_kelamin IN ('L', 'P')),
	tanggal_lahir		DATE,
	nik					VARCHAR(16),
	npwp				VARCHAR(15),
	pekerjaan			VARCHAR(50),
	segmen_debitur		VARCHAR(20)			CHECK(segmen_debitur IN ('Mikro', 'Kecil', 'Menengah', 'Konsumer')),
	kota				VARCHAR(50),
	penghasilan_bulanan	BIGINT				CHECK(penghasilan_bulanan > 0),
	tanggal_bergabung	DATE,
	created_at			TIMESTAMP			DEFAULT NOW()
);


--PRODUCTION: fasilitas_kredit
CREATE TABLE IF NOT EXISTS kredit.fasilitas_kredit(
	id_fasilitas			VARCHAR(20)		PRIMARY KEY,
	cif						VARCHAR(20)		NOT NULL REFERENCES kredit.debitur(cif),
	produk_kredit			VARCHAR(50)		NOT NULL,
	segmen_kredit			VARCHAR(20),
	tanggal_realisasi		DATE			NOT NULL,
	tanggal_jatuh_tempo		DATE			NOT NULL,
	tenor_bulan				INT 			CHECK(tenor_bulan > 0),
	plafon					BIGINT			CHECK(plafon > 0),
	suku_bunga				NUMERIC(5,2)	CHECK(suku_bunga >= 0),
	outstanding				BIGINT,
	kolektibilitas_kode		INT				CHECK(kolektibilitas_kode BETWEEN 1 AND 5),
	kolektibilitas_label	VARCHAR(50),
	hari_tunggakan			INT 			DEFAULT 0,
	jenis_agunan			VARCHAR(50),
	nilai_agunan			BIGINT			DEFAULT 0,
	status_kredit			VARCHAR(20)		CHECK(status_kredit IN ('Aktif', 'Lunas', 'Hapus Buku')),
	created_at				TIMESTAMP		DEFAULT NOW()
);


--PRODUCTION: pembayaran
CREATE TABLE IF NOT EXISTS kredit.pembayaran(
	id_pembayaran					VARCHAR(20)		PRIMARY KEY,
	id_fasilitas					VARCHAR(20) 	NOT NULL REFERENCES kredit.fasilitas_kredit(id_fasilitas),
	tanggal_jatuh_tempo_angsuran	DATE			NOT NULL,
	tanggal_bayar					DATE,
	angsuran_pokok					BIGINT,
	angsuran_bunga					BIGINT,
	total_angsuran					BIGINT,
	nominal_bayar					BIGINT 			DEFAULT 0,
	status_pembayaran				VARCHAR(20)		CHECK(status_pembayaran IN ('Tepat Waktu', 'Terlambat', 'Tidak Bayar')),
	denda							BIGINT			DEFAULT 0,
	ke_angsuran						INT,
	created_at						TIMESTAMP   	DEFAULT NOW()
);


--#### Indexing for Query Perform ####---
CREATE INDEX IF NOT EXISTS idx_fasilitas_cif
	ON kredit.fasilitas_kredit(cif);

CREATE INDEX IF NOT EXISTS idx_fasilitas_kolektibilitas
	ON kredit.fasilitas_kredit(kolektibilitas_kode);

CREATE INDEX IF NOT EXISTS idx_fasilitas_status
	ON kredit.fasilitas_kredit(status_kredit);

CREATE INDEX IF NOT EXISTS idx_pembayaran_fasilitas
	ON kredit.pembayaran(id_fasilitas);

CREATE INDEX IF NOT EXISTS idx_pembayaran_status
	ON kredit.pembayaran(status_pembayaran);

CREATE INDEX IF NOT EXISTS idx_pembayaran_tgl_jatuh
	ON kredit.pembayaran(tanggal_jatuh_tempo_angsuran);
