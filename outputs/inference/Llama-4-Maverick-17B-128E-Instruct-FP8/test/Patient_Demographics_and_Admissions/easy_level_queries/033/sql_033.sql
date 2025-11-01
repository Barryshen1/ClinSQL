WITH dialysis_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.hadm_id = proc.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND proc.icd_code IN (
      -- ICD-9 codes for dialysis
      '39.95', '54.98',
      -- ICD-10 codes for dialysis
      '5A1D7ZZ', '5A1D8ZZ', '5A1D9ZZ'
    )
),
los_data AS (
  SELECT a.hadm_id, DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN dialysis_patients dp ON a.subject_id = dp.subject_id
)
SELECT STDDEV(los) AS sd_los
FROM los_data;