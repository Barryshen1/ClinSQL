WITH pci_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%percutaneous coronary intervention%'
     OR LOWER(long_title) LIKE '%angioplasty%'
     OR (icd_version = 9 AND icd_code IN ('3601', '3602', '3603', '3604', '3605', '3606', '3607'))
     OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = '021')
),
first_pci AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY p.chartdate) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN pci_codes pc
    ON p.icd_code = pc.icd_code AND p.icd_version = pc.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    -- Compute age at time of procedure
    AND (p.chartdate >= DATETIME(pat.anchor_year, 1, 1, 0, 0, 0))
    AND (EXTRACT(YEAR FROM p.chartdate) - pat.anchor_year + pat.anchor_age) BETWEEN 52 AND 62
),
first_pci_index_admission AS (
  SELECT subject_id, hadm_id, dischtime
  FROM first_pci
  WHERE rn = 1
),
readmissions AS (
  SELECT DISTINCT
    f.subject_id,
    1 AS readmitted
  FROM first_pci_index_admission f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
    AND a.admittime > f.dischtime
    AND a.admittime <= DATETIME_ADD(f.dischtime, INTERVAL 30 DAY)
)
SELECT
  AVG(COALESCE(r.readmitted, 0)) AS thirty_day_readmission_rate
FROM first_pci_index_admission f
LEFT JOIN readmissions r ON f.subject_id = r.subject_id;