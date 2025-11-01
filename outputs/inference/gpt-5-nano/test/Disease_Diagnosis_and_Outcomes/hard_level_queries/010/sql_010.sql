WITH comorb_mapping AS (
  -- pattern-based mapping for major Charlson comorbidities (ICD-10 patterns)
  SELECT 'I21%' AS pattern UNION ALL
  SELECT 'I22%',  UNION ALL
  SELECT 'I50%',  UNION ALL
  SELECT 'I60%', UNION ALL
  SELECT 'I61%', UNION ALL
  SELECT 'I62%', UNION ALL
  SELECT 'I63%', UNION ALL
  SELECT 'I64%', UNION ALL
  SELECT 'I69%', UNION ALL
  SELECT 'F01%', UNION ALL
  SELECT 'F02%', UNION ALL
  SELECT 'F03%', UNION ALL
  SELECT 'J40%', UNION ALL
  SELECT 'J41%', UNION ALL
  SELECT 'J42%', UNION ALL
  SELECT 'J43%', UNION ALL
  SELECT 'J44%', UNION ALL
  SELECT 'J45%', UNION ALL
  SELECT 'J46%', UNION ALL
  SELECT 'J47%', UNION ALL
  SELECT 'E10%', UNION ALL
  SELECT 'E11%', UNION ALL
  SELECT 'E12%', UNION ALL
  SELECT 'E13%', UNION ALL
  SELECT 'E14%'
),
risk_by_hadm AS (
  -- risk_score: simple count of comorbid patterns matched on ICD-10 codes
  SELECT di.hadm_id, COUNT(*) AS risk_score
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN comorb_mapping m
    ON di.icd_version = 10
   AND di.icd_code LIKE m.pattern
  GROUP BY di.hadm_id
),
population AS (
  -- base population: male, age 39-49
  SELECT
     a.hadm_id,
     a.subject_id,
     a.admittime,
     a.dischtime,
     a.deathtime,
     p.gender,
     p.anchor_age,
     COALESCE(rb.risk_score, 0) AS risk_score
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN risk_by_hadm rb
    ON a.hadm_id = rb.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
dka_set AS (
  -- admissions with DKA (ICD-10 E10.x)
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'E10%'
),
augmented AS (
  SELECT
     pop.*,
     CASE WHEN pop.hadm_id IN (SELECT hadm_id FROM dka_set) THEN 1 ELSE 0 END AS is_dka,
     CASE WHEN pop.deathtime IS NOT NULL AND TIMESTAMP_DIFF(pop.deathtime, pop.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
     TIMESTAMP_DIFF(pop.dischtime, pop.admittime, DAY) AS los_days,
     -- cardiovascular complications: MI, heart failure
     CASE WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_cv
        WHERE di_cv.hadm_id = pop.hadm_id
          AND di_cv.icd_version = 10
          AND (di_cv.icd_code LIKE 'I21%' OR di_cv.icd_code LIKE 'I22%' OR di_cv.icd_code LIKE 'I50%')
     ) THEN 1 ELSE 0 END AS has_cardio,
     -- neurologic complications: epilepsy/hemis/stroke-spectrum
     CASE WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_nv
        WHERE di_nv.hadm_id = pop.hadm_id
          AND di_nv.icd_version = 10
          AND (di_nv.icd_code LIKE 'G40%' OR di_nv.icd_code LIKE 'G41%' OR di_nv.icd_code LIKE 'G45%' OR di_nv.icd_code LIKE 'G46%' OR di_nv.icd_code LIKE 'G47%')
     ) THEN 1 ELSE 0 END AS has_neuro
  FROM population pop
),
risk_percentile AS (
  -- risk percentile for each admission (relative to all male 39-49)
  SELECT hadm_id, risk_score,
         PERCENT_RANK() OVER (ORDER BY risk_score) * 100 AS risk_percentile
  FROM augmented
)
SELECT
  -- mean risk score: DKA vs all males (the entire male 39-49 population)
  AVG(CASE WHEN is_dka = 1 THEN risk_score END) AS mean_risk_score_dka,
  AVG(CASE WHEN is_dka = 0 THEN risk_score END) AS mean_risk_score_all_males_39_49,
  -- 30-day mortality: DKA vs all
  AVG(CASE WHEN is_dka = 1 THEN mortality_30d END) AS thirty_day_mortality_dka,
  AVG(CASE WHEN is_dka = 0 THEN mortality_30d END) AS thirty_day_mortality_all_males_39_49,
  -- cardiovascular complication rates
  AVG(CASE WHEN is_dka = 1 THEN has_cardio END) AS cardio_rate_dka,
  AVG(CASE WHEN is_dka = 0 THEN has_cardio END) AS cardio_rate_all_males_39_49,
  -- neurologic complication rates
  AVG(CASE WHEN is_dka = 1 THEN has_neuro END) AS neuro_rate_dka,
  AVG(CASE WHEN is_dka = 0 THEN has_neuro END) AS neuro_rate_all_males_39_49,
  -- mean survivor LOS
  AVG(CASE WHEN is_dka = 1 AND mortality_30d = 0 THEN los_days END) AS mean_survivor_los_dka,
  AVG(CASE WHEN is_dka = 0 AND mortality_30d = 0 THEN los_days END) AS mean_survivor_los_all_males_39_49,
  -- risk percentile for the DKA matched profile
  (SELECT AVG(risk_percentile)
     FROM risk_percentile rp
     WHERE rp.hadm_id IN (SELECT hadm_id FROM dka_set)
  ) AS avg_risk_percentile_dka
FROM augmented;