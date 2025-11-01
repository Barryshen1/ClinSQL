WITH pci_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'percutaneous.*coronary|ptca|coronary.*angioplasty')
),
has_pci AS (
  SELECT DISTINCT pi.subject_id, pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN pci_codes pc
    ON pi.icd_code = pc.icd_code AND pi.icd_version = pc.icd_version
),
first_pci_adm AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
           ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN has_pci hp
      ON a.subject_id = hp.subject_id AND a.hadm_id = hp.hadm_id
    WHERE a.hospital_expire_flag = 0
  )
  WHERE rn = 1
),
index_adms AS (
  SELECT fpa.*, p.gender, p.anchor_age
  FROM first_pci_adm fpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fpa.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 52 AND 62
),
readmission_check AS (
  SELECT ia.*,
         EXISTS(
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
           WHERE a.subject_id = ia.subject_id
             AND a.hadm_id <> ia.hadm_id
             AND a.admittime > ia.dischtime
             AND a.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
         ) AS has_readmission
  FROM index_adms ia
)
SELECT
  COUNT(*) AS total_patients,
  SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END) AS num_readmitted,
  ROUND(AVG(CASE WHEN has_readmission THEN 1.0 ELSE 0.0 END) * 100, 2) AS readmission_rate_percent
FROM readmission_check;