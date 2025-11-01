WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 81 AND 91
),
admissions_with_age_and_diagnosis AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_filter p ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id AND d.seq_num = 1
    AND ((d.icd_version = 9 AND d.icd_code LIKE '584%') 
         OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%'))
  )
)
SELECT 
  APPROX_QUANTILES(los_hours, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_hours, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(los_hours, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_hours, 4)[OFFSET(3)] - APPROX_QUANTILES(los_hours, 4)[OFFSET(1)] AS iqr
FROM admissions_with_age_and_diagnosis;