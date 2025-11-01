WITH pneumonia_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
), first_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id 
      ORDER BY a.admittime
    ) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 51 AND 61
), pneumonia_admissions AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fa.hadm_id = diag.hadm_id
  INNER JOIN pneumonia_codes pc
    ON diag.icd_code = pc.icd_code
    AND diag.icd_version = pc.icd_version
  WHERE fa.admission_rank = 1
), icu_los_per_admission AS (
  SELECT 
    pa.hadm_id,
    SUM(icu.los) AS total_icu_los_days
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pa.hadm_id = icu.hadm_id
  GROUP BY pa.hadm_id
)
SELECT 
  APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM icu_los_per_admission;