WITH pci_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(long_title, r'(?i)percutaneous(\s+.*)?\s+coronary') OR
    REGEXP_CONTAINS(long_title, r'(?i)PCI') OR
    REGEXP_CONTAINS(long_title, r'(?i)angioplasty.*coronary') OR
    REGEXP_CONTAINS(long_title, r'(?i)PTCA')
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    -- Compute age at admission: anchor_age + (admission year - anchor_year)
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
),
pci_admissions AS (
  SELECT DISTINCT proc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN pci_codes pc
    ON proc.icd_code = pc.icd_code
    AND proc.icd_version = pc.icd_version
),
icu_stays AS (
  SELECT DISTINCT
    icu.stay_id,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN cohort c
    ON icu.hadm_id = c.hadm_id
    AND icu.subject_id = c.subject_id
  INNER JOIN pci_admissions pa
    ON c.hadm_id = pa.hadm_id
  WHERE c.age BETWEEN 68 AND 78
)
SELECT 
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM icu_stays;