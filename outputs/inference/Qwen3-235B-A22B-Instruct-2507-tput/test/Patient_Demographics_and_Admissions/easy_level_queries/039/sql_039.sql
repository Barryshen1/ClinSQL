WITH patients_with_pneumonia AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'J18%'  -- Common ICD-10 code for pneumonia
    AND di.icd_version = 10
),
cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS icu_stay_order
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN patients_with_pneumonia pp ON p.subject_id = pp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile
FROM cohort
WHERE icu_stay_order = 1;