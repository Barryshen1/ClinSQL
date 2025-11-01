WITH eligible_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        -- Chest pain codes (ICD-10)
        (diag.icd_code LIKE 'R07%' AND diag.icd_version = 10) OR
        -- AMI codes (ICD-10 I21.*)
        (diag.icd_code LIKE 'I21%' AND diag.icd_version = 10)
    )
),
first_troponin AS (
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ea.hadm_id = le.hadm_id
    AND le.itemid = 50911  -- hs-TnT
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ea.hadm_id 
    ORDER BY le.charttime
  ) = 1
  AND le.valuenum > 0.014  -- ULN condition
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS q1_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] AS q3_initial_troponin
FROM first_troponin;