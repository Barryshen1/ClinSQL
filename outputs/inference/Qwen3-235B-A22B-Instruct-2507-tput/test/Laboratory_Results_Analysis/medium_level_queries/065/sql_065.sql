WITH patient_ami AS (
  SELECT DISTINCT a.hadm_id, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
    AND d.icd_code LIKE 'I21%' 
    AND d.icd_version = 10
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(CAST(ft.valuenum AS FLOAT64), 1000)[OFFSET(250)] AS q25,
  APPROX_QUANTILES(CAST(ft.valuenum AS FLOAT64), 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(CAST(ft.valuenum AS FLOAT64), 1000)[OFFSET(750)] AS q75
FROM first_troponin ft
JOIN patient_ami pa ON ft.hadm_id = pa.hadm_id
WHERE ft.rn = 1
  AND ft.valuenum > 0.04;