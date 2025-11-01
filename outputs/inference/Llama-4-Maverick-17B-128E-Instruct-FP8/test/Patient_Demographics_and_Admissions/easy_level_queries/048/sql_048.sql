WITH heart_failure_patients AS (
  SELECT DISTINCT d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  WHERE (d.icd_version = 9 AND d.long_title LIKE '%HEART FAILURE%') 
     OR (d.icd_version = 10 AND d.long_title LIKE '%HEART FAILURE%')
),
eligible_patients AS (
  SELECT p.subject_id, MIN(a.admittime) AS first_admit_time, MIN(a.dischtime) AS first_discharge_time
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.icd_code IN (SELECT icd_code FROM heart_failure_patients)
  GROUP BY p.subject_id
),
los_quantiles AS (
  SELECT 
    APPROX_QUANTILES(DATE_DIFF(first_discharge_time, first_admit_time, DAY), 100) AS quantiles
  FROM eligible_patients
)
SELECT 
  quantiles[OFFSET(25)] AS q1,
  quantiles[OFFSET(75)] AS q3
FROM los_quantiles;