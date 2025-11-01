WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    icd_code LIKE 'A41%' OR 
    icd_code IN ('R6520', 'R6521')
  )
  AND icd_version = 10
),
patients_with_sepsis AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN sepsis_codes s
    ON diag.icd_code = s.icd_code AND diag.icd_version = 10
),
cohort AS (
  SELECT 
    p.subject_id,
    icu.stay_id,
    icu.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN patients_with_sepsis ps
    ON adm.subject_id = ps.subject_id AND adm.hadm_id = ps.hadm_id
  WHERE p.gender = 'F'
    -- Calculate age at admission
    AND (EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 58 AND 68
)
SELECT 
  PERCENTILE_CONT(icu_los, 0.5) OVER() AS median_icu_los
FROM cohort
LIMIT 1;