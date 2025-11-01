WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    di.icd_code AS primary_diagnosis_code,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
    AND di.icd_code IN ('K92.2', 'K62.5', 'K62.3', 'K62.4', 'K62.6')
),
complications AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' THEN 1 ELSE 0 END) AS sepsis,
    MAX(CASE WHEN icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki,
    MAX(CASE WHEN icd_code LIKE 'J96%' THEN 1 ELSE 0 END) AS resp_failure,
    MAX(CASE WHEN icd_code LIKE 'I21%' THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN icd_code LIKE 'I63%' THEN 1 ELSE 0 END) AS stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_complications AS (
  SELECT 
    c.*,
    COALESCE(comp.sepsis, 0) + COALESCE(comp.aki, 0) + COALESCE(comp.resp_failure, 0) + COALESCE(comp.mi, 0) + COALESCE(comp.stroke, 0) AS composite_score,
    CASE WHEN c.dod IS NOT NULL AND c.dod <= c.admittime + INTERVAL 90 DAY THEN 1 ELSE 0 END AS is_90_day_dead,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM cohort c
  LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM cohort_with_complications
)
SELECT 
  quintile,
  COUNT(*) AS N,
  AVG(is_90_day_dead) AS mortality_rate_90_day,
  AVG(CASE WHEN composite_score >= 1 THEN 1 ELSE 0 END) AS major_complication_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN is_90_day_dead = 0 THEN los ELSE NULL END) AS median_los_survivors
FROM quintiles
GROUP BY quintile
ORDER BY quintile;