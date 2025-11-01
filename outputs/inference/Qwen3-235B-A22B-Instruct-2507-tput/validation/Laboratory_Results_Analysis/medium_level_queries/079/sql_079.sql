WITH troponin_t_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'troponin t'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_t_item tti ON le.itemid = tti.itemid
  WHERE le.valuenum IS NOT NULL
),
initial_troponin AS (
  SELECT subject_id, hadm_id, troponin_t_value
  FROM first_troponin
  WHERE rn = 1 AND troponin_t_value > 0.01
),
ami_or_chest_pain_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    LOWER(long_title) LIKE '%myocardial infarction%' OR
    LOWER(long_title) LIKE '%acute%' AND LOWER(long_title) LIKE '%mi%' OR
    LOWER(long_title) LIKE '%chest pain%'
  )
  -- Adding common ICD-10 codes explicitly for safety
  UNION DISTINCT
  SELECT 'I21.9' AS icd_code UNION DISTINCT
  SELECT 'I21.02' UNION DISTINCT
  SELECT 'I21.1' UNION DISTINCT
  SELECT 'I21.2' UNION DISTINCT
  SELECT 'I21.3' UNION DISTINCT
  SELECT 'I21.4' UNION DISTINCT
  SELECT 'I22' UNION DISTINCT
  SELECT 'R07.9'
),
qualifying_admissions AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ami_or_chest_pain_codes c ON di.icd_code = c.icd_code
),
eligible_patients AS (
  SELECT
    p.subject_id,
    it.troponin_t_value
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN initial_troponin it ON p.subject_id = it.subject_id
  INNER JOIN qualifying_admissions qa ON it.hadm_id = qa.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
)
SELECT
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(75)] AS p75,
  MIN(troponin_t_value) AS min_value,
  MAX(troponin_t_value) AS max_value
FROM eligible_patients;