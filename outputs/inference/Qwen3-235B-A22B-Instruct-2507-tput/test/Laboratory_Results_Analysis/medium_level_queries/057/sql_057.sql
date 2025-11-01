WITH acs_patients AS (
  SELECT DISTINCT adm.hadm_id, adm.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND diag.icd_version = 10
    AND (
      d_diag.icd_code LIKE 'I21%' OR 
      d_diag.icd_code = 'I20.0'
    )
),
troponin_t AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t'
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN troponin_t tt ON le.itemid = tt.itemid
  INNER JOIN acs_patients ap ON le.hadm_id = ap.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= (SELECT admittime FROM `physionet-data.mimiciv_3_1_hosp`.admissions a WHERE a.hadm_id = le.hadm_id)
    AND le.charttime <= (SELECT COALESCE(dischtime, admittime) FROM `physionet-data.mimiciv_3_1_hosp`.admissions a WHERE a.hadm_id = le.hadm_id)
)
SELECT
  CASE
    WHEN valuenum <= 0.04 THEN 'normal'
    WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline'
    WHEN valuenum > 0.1 THEN 'elevated'
    ELSE 'unknown'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM first_troponin
WHERE rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;