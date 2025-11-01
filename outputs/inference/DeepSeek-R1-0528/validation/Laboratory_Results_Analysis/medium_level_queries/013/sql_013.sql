WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 50 AND 60
    AND (
      (di.icd_version = 9 AND (di.icd_code LIKE '786.5%' OR di.icd_code LIKE '410%'))
      OR 
      (di.icd_version = 10 AND (di.icd_code LIKE 'R07%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
    )
),

initial_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c
    ON l.hadm_id = c.hadm_id
  WHERE 
    l.itemid = 51003  -- hs-TnT itemid
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),

final_cohort AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    it.troponin_value
  FROM cohort c
  INNER JOIN initial_troponin it
    ON c.hadm_id = it.hadm_id
  WHERE it.troponin_value > 0.014  -- ULN threshold
),

stats AS (
  SELECT 
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(troponin_value) AS mean_tnt
  FROM final_cohort
),

quartiles AS (
  SELECT 
    APPROX_QUANTILES(troponin_value, 4) AS q
  FROM final_cohort
)

SELECT 
  patient_count,
  admission_count,
  mean_tnt,
  q[OFFSET(1)] AS q1_tnt,
  q[OFFSET(2)] AS median_tnt,
  q[OFFSET(3)] AS q3_tnt,
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr_tnt
FROM stats, quartiles;