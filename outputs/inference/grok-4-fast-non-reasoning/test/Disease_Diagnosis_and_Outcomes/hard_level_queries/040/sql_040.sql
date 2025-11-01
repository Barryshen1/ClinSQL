WITH ich_cohort AS (
  -- Base cohort: females 69-79
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.admission_type != 'OBSERVATION'
),
ich_admissions AS (
  -- ICH diagnoses (ICD-9/10 codes)
  SELECT DISTINCT 
    c.*,
    d.icd_code,
    d.icd_version
  FROM ich_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I6[0-2]%' AND NOT d.icd_code LIKE 'I63%')  -- I60-I62, exclude ischemic I63
),
gcs_scores AS (
  -- Min GCS within 24h (ICU chartevents)
  SELECT 
    subject_id,
    hadm_id,
    MIN(valuenum) AS min_gcs
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  WHERE ce.itemid IN (198, 220, 372, 374, 380, 381, 390, 223908, 223900)  -- GCS components/totals
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 1 DAY)
  GROUP BY subject_id, hadm_id
),
comorb_flags AS (
  -- Simplified comorbidities from diagnoses
  SELECT 
    subject_id,
    hadm_id,
    SUM(CASE 
      WHEN diag.icd_code LIKE '401%' OR diag.icd_code LIKE '402%' OR diag.icd_code LIKE '403%' OR diag.icd_code LIKE '404%' OR diag.icd_code LIKE '405%' 
           OR diag.icd_code LIKE 'I10%' OR diag.icd_code LIKE 'I11%' OR diag.icd_code LIKE 'I12%' OR diag.icd_code LIKE 'I13%' OR diag.icd_code LIKE 'I14%' OR diag.icd_code LIKE 'I15%' OR diag.icd_code LIKE 'I16%' THEN 1 ELSE 0 END +
      CASE WHEN diag.icd_code = '250' OR diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%' OR diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%' THEN 1 ELSE 0 END +
      CASE WHEN diag.icd_code = '428' OR diag.icd_code = 'I50' THEN 1 ELSE 0 END +
      CASE WHEN diag.icd_code = '585' OR diag.icd_code LIKE 'N18%' THEN 1 ELSE 0 END
    ) AS comorb_sum
  FROM ich_admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ich_admissions.subject_id = diag.subject_id AND ich_admissions.hadm_id = diag.hadm_id
  GROUP BY subject_id, hadm_id
),
risk_and_outcomes AS (
  SELECT 
    ia.*,
    COALESCE(gs.min_gcs, 15) AS min_gcs,  -- Impute missing GCS to normal
    COALESCE(cf.comorb_sum, 0) AS comorb_sum,
    -- Composite risk score
    (ia.anchor_age - 60) + (16 - COALESCE(gs.min_gcs, 15)) + (COALESCE(cf.comorb_sum, 0) * 3) AS risk_score,
    -- 30-day mortality
    CASE WHEN ia.deathtime IS NOT NULL 
         AND ia.deathtime <= DATETIME_ADD(ia.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END AS mortality_30d,
    -- LOS in days (for survivors)
    DATE_DIFF(ia.dischtime, ia.admittime, DAY) AS los_days,
    -- Major complications (simplified: e.g., sepsis/pneumonia diagnoses)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = ia.subject_id AND diag.hadm_id = ia.hadm_id
        AND (diag.icd_code LIKE '995.9%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE '486%' OR diag.icd_code LIKE 'J18%')
    ) THEN 1 ELSE 0 END AS has_comp
  FROM ich_admissions ia
  LEFT JOIN gcs_scores gs
    ON ia.subject_id = gs.subject_id AND ia.hadm_id = gs.hadm_id
  LEFT JOIN comorb_flags cf
    ON ia.subject_id = cf.subject_id AND ia.hadm_id = cf.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM risk_and_outcomes
),
summary AS (
  SELECT 
    quintile,
    COUNT(*) AS n,
    ROUND(AVG(mortality_30d) * 100, 1) AS mortality_30d_pct,
    ROUND(AVG(has_comp) * 100, 1) AS major_comp_pct
  FROM quintiles
  GROUP BY quintile
)
SELECT 
  s.*,
  (SELECT PERCENTILE_CONT(los_days, 0.5) 
   FROM quintiles q 
   WHERE q.quintile = s.quintile AND q.mortality_30d = 0) AS median_los_survivors
FROM summary s
ORDER BY quintile;