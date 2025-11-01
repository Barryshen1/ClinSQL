WITH akipatients AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 37 AND 47
  AND d.seq_num = 1  -- Primary diagnosis
  AND d.icd_version = 10  -- Assuming ICD-10; adjust as necessary
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    WHERE d.icd_code = dd.icd_code AND dd.icd_version = d.icd_version
    AND LOWER(dd.long_title) LIKE '%acute kidney injury%'  -- Simplified; actual implementation may vary based on specific ICD codes used for AKI
  )
),
los_data AS (
  SELECT a.hadm_id, DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN akipatients ak ON a.hadm_id = ak.hadm_id
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75th_los
FROM los_data;