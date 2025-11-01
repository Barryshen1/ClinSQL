WITH pneumonia_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),
filtered_patients AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN pneumonia_admissions pa
    ON a.hadm_id = pa.hadm_id
  WHERE p.gender = 'F'
),
age_los AS (
  SELECT 
    hadm_id,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM filtered_patients
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM age_los
WHERE age_at_admission BETWEEN 49 AND 59;