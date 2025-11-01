WITH pneumonia_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.dod,
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Count distinct non-pneumonia ICD-10 diagnoses as risk score
    COUNT(DISTINCT CASE WHEN di.icd_code NOT LIKE 'J18%' THEN di.icd_code ELSE NULL END) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND di.icd_code LIKE 'J18%'  -- pneumonia codes
    AND di.icd_version = 10
  GROUP BY p.subject_id, p.gender, p.anchor_age, p.dod, a.hadm_id, a.admittime, a.dischtime
),
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM pneumonia_cohort
),
complications AS (
  SELECT 
    q.hadm_id,
    -- Cardiovascular complication: any cardiovascular ICD code
    MAX(CASE WHEN card.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS cardiovascular_complication,
    -- Neurologic complication: any neurologic ICD code
    MAX(CASE WHEN neuro.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS neurologic_complication
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON q.hadm_id = di.hadm_id
  LEFT JOIN (SELECT DISTINCT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
             WHERE icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I50%' 
                OR icd_code LIKE 'I48%' OR icd_code LIKE 'I44%' OR icd_code LIKE 'I45%' 
                OR icd_code LIKE 'I46%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I49%') card
    ON di.icd_code = card.icd_code
  LEFT JOIN (SELECT DISTINCT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
             WHERE icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' 
                OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' OR icd_code LIKE 'G40%' 
                OR icd_code LIKE 'G41%' OR icd_code LIKE 'G93.1' OR icd_code LIKE 'G93.4') neuro
    ON di.icd_code = neuro.icd_code
  GROUP BY q.hadm_id
),
outcomes AS (
  SELECT 
    q.*,
    -- 30-day mortality: death within 30 days of admission
    CASE WHEN q.dod IS NOT NULL AND DATE_DIFF(DATE(q.dod), DATE(q.admittime), DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
    c.cardiovascular_complication,
    c.neurologic_complication,
    -- LOS in days for survivors (if not died within 30 days)
    CASE WHEN (q.dod IS NULL OR DATE_DIFF(DATE(q.dod), DATE(q.admittime), DAY) > 30) 
         THEN DATE_DIFF(DATE(q.dischtime), DATE(q.admittime), DAY) 
         ELSE NULL END AS los_survivors
  FROM quintiles q
  LEFT JOIN complications c
    ON q.hadm_id = c.hadm_id
)
SELECT 
  quintile,
  COUNT(*) AS n_patients,
  ROUND(100 * AVG(mortality_30d), 2) AS mortality_30d_percent,
  ROUND(100 * AVG(cardiovascular_complication), 2) AS cardiovascular_complication_percent,
  ROUND(100 * AVG(neurologic_complication), 2) AS neurologic_complication_percent,
  APPROX_QUANTILES(los_survivors, 100)[OFFSET(50)] AS median_los_survivors
FROM outcomes
GROUP BY quintile
ORDER BY quintile;