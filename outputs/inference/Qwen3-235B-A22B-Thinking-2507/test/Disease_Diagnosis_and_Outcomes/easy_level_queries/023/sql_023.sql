WITH patient_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id 
    AND d_icd.seq_num = 1
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
    AND (
      (d_icd.icd_version = 9 AND (d_icd.icd_code LIKE '48[0-6]%' OR d_icd.icd_code = '507.0'))
      OR
      (d_icd.icd_version = 10 AND (d_icd.icd_code LIKE 'J1[2-8]%' OR d_icd.icd_code = 'J69.0'))
    )
),
los_data AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60) AS los_days
  FROM patient_cohort
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM los_data;