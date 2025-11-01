WITH pci_codes AS (
  -- ICD-9 codes for PCI
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 9 AND icd_code LIKE '36.0%'
  UNION DISTINCT
  -- ICD-10 codes for PCI
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 10 AND icd_code LIKE '027%'
),
cohort AS (
  -- Patients: male, age 52-62
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 52 AND 62
),
first_pci AS (
  -- First PCI per patient
  SELECT 
    cohort.subject_id,
    proc.hadm_id,
    proc.chartdate as pci_date,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    ROW_NUMBER() OVER (PARTITION BY cohort.subject_id ORDER BY proc.chartdate) as rn
  FROM cohort
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON cohort.subject_id = proc.subject_id
  INNER JOIN pci_codes
    ON proc.icd_code = pci_codes.icd_code 
    AND proc.icd_version = pci_codes.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON proc.hadm_id = adm.hadm_id
  WHERE adm.deathtime IS NULL  -- exclude if died during index admission
)
-- Index admissions with first PCI
, index_adm AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM first_pci
  WHERE rn = 1
)
-- Find readmissions within 30 days
, readmissions AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id as index_hadm,
    ia.dischtime as index_discharge,
    next_adm.hadm_id as readmit_hadm,
    next_adm.admittime as readmit_time,
    DATE_DIFF(next_adm.admittime, ia.dischtime, DAY) as days_to_readmit
  FROM index_adm ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON ia.subject_id = next_adm.subject_id
    AND next_adm.admittime > ia.dischtime
    AND DATE_DIFF(next_adm.admittime, ia.dischtime, DAY) <= 30
)
-- Calculate average readmission rate
SELECT 
  COUNT(DISTINCT subject_id) as total_patients,
  COUNT(DISTINCT CASE WHEN readmit_hadm IS NOT NULL THEN subject_id END) as readmitted_patients,
  ROUND(COUNT(DISTINCT CASE WHEN readmit_hadm IS NOT NULL THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id), 2) as readmission_rate_percent
FROM readmissions;