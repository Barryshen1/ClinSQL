WITH patient_selection AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 68 AND 78
),
admissions_with_diagnosis AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_selection p ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id AND (LOWER(dicd.long_title) LIKE '%pneumonia%' OR LOWER(dicd.long_title) LIKE '%copd%')
  )
),
hospital_los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los
  FROM admissions_with_diagnosis
)
SELECT APPROX_QUANTILES(los, 100)[OFFSET(75)] AS percentile_75th_los
FROM hospital_los;