WITH
-- Get male patients aged 52-62
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get PCI procedure codes (more specific)
pci_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- More specific PCI codes
    (icd_code IN ('00.66', '36.01', '36.02', '36.05', '36.06', '36.07', '36.09')
     OR icd_code LIKE '02.7%')
    AND icd_version IN (9, 10)
),

-- Get first PCI procedure for each patient
first_pci_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS pci_sequence
  FROM
    eligible_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.subject_id = proc.subject_id AND a.hadm_id = proc.hadm_id
  JOIN
    pci_codes pc ON proc.icd_code = pc.icd_code AND proc.icd_version = pc.icd_version
),

-- Get only the first PCI admission for each patient
index_admissions AS (
  SELECT
    subject_id,
    index_hadm_id,
    index_admittime,
    index_dischtime
  FROM
    first_pci_admissions
  WHERE
    pci_sequence = 1
),

-- Verify that the index admission actually had a PCI procedure
valid_index_admissions AS (
  SELECT
    ia.*
  FROM
    index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON ia.subject_id = proc.subject_id AND ia.index_hadm_id = proc.hadm_id
  JOIN
    pci_codes pc ON proc.icd_code = pc.icd_code AND proc.icd_version = pc.icd_version
),

-- Find any readmissions within 30 days of discharge from index admission
readmissions AS (
  SELECT DISTINCT
    ia.subject_id,
    ia.index_hadm_id,
    a.hadm_id AS readmission_hadm_id,
    a.admittime AS readmission_admittime
  FROM
    valid_index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON ia.subject_id = a.subject_id
  WHERE
    a.admittime > ia.index_dischtime
    AND a.admittime <= DATETIME_ADD(ia.index_dischtime, INTERVAL 30 DAY)
    AND a.hadm_id != ia.index_hadm_id
    AND a.hospital_expire_flag = 0  -- Exclude patients who died during readmission
)

-- Calculate readmission rate with protection against division by zero
SELECT
  COUNT(DISTINCT ia.subject_id) AS total_patients,
  COUNT(DISTINCT r.subject_id) AS patients_with_readmission,
  CASE
    WHEN COUNT(DISTINCT ia.subject_id) = 0 THEN 0
    ELSE COUNT(DISTINCT r.subject_id) * 100.0 / COUNT(DISTINCT ia.subject_id)
  END AS readmission_rate_percentage
FROM
  valid_index_admissions ia
LEFT JOIN
  readmissions r ON ia.subject_id = r.subject_id;