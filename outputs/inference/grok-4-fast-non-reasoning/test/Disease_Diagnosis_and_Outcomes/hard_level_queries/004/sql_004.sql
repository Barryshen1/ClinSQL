WITH cohort AS (
  -- Select unique admissions with at least one qualifying admission
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Simplified LOS in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  -- Filters: Female, age 44-54, ICH (ICD-10 I61*)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND icd.icd_code LIKE 'I61%'
    AND a.admittime < COALESCE(p.dod, '2100-01-01')  -- Exclude if died before admission (rare)
),

first_icu_stays AS (
  -- Get first ICU stay per admission for risk scoring
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN cohort c ON icu.subject_id = c.subject_id AND icu.hadm_id = c.hadm_id
  )
  WHERE rn = 1
),

risk_scores AS (
  -- Calculate simplified composite risk score per admission (0-5 scale)
  SELECT
    c.*,
    COALESCE(
      SUM(
        CASE
          WHEN MAX(CASE WHEN di.itemid = 223900 AND ce.valuenum < 15 THEN 1 ELSE 0 END) OVER (w) = 1 THEN 1 ELSE 0
          WHEN MAX(CASE WHEN di.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) OVER (w) = 1 THEN 1 ELSE 0  -- HR
          WHEN MAX(CASE WHEN di.itemid = 220179 AND ce.valuenum < 90 THEN 1 ELSE 0 END) OVER (w) = 1 THEN 1 ELSE 0   -- SBP (corrected itemid)
          WHEN MAX(CASE WHEN di.itemid = 50912 AND ce.valuenum > 1.5 THEN 1 ELSE 0 END) OVER (w) = 1 THEN 1 ELSE 0   -- Creatinine
          WHEN c.anchor_age > 50 THEN 1 ELSE 0  -- Age >50
        END
      ) OVER (w),
      0
    ) AS risk_score
  FROM cohort c
  LEFT JOIN first_icu_stays fis ON c.subject_id = fis.subject_id AND c.hadm_id = fis.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id 
    AND c.hadm_id = ce.hadm_id 
    AND (fis.stay_id IS NULL OR ce.stay_id = fis.stay_id)
    AND ce.charttime >= COALESCE(fis.intime, c.admittime)
    AND ce.charttime <= DATETIME_ADD(COALESCE(fis.intime, c.admittime), INTERVAL 1 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.category IN ('Routine Vital Signs', 'Neurological', 'Labs') OR di.itemid IS NULL  -- Allow non-matches for age-only
  WINDOW w AS (PARTITION BY c.subject_id, c.hadm_id)
  GROUP BY c.subject_id, c.hadm_id, c.gender, c.anchor_age, c.admittime, c.dischtime, c.hospital_expire_flag, c.los_days
),

complications AS (
  -- Flag complications per admission
  SELECT
    rs.*,
    MAX(CASE WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I46%' THEN 1 ELSE 0 END) 
      OVER (PARTITION BY rs.subject_id, rs.hadm_id) AS cardiac_flag,
    MAX(CASE WHEN (d.icd_code LIKE 'G93.6%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'G40%')
             AND d.icd_code NOT LIKE 'I61%' THEN 1 ELSE 0 END) 
      OVER (PARTITION BY rs.subject_id, rs.hadm_id) AS neuro_flag
  FROM risk_scores rs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON rs.subject_id = d.subject_id AND rs.hadm_id = d.hadm_id
),

quartiles AS (
  -- Assign quartiles based on risk_score (per admission)
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM complications
),

survivor_los AS (
  -- Compute median LOS for survivors per quartile
  SELECT
    risk_quartile,
    PERCENTILE_CONT(0.5) OVER (PARTITION BY risk_quartile) AS median_los_survivors_days
  FROM quartiles
  WHERE hospital_expire_flag = 0
)

-- Final aggregation per quartile (admission-level)
SELECT
  q.risk_quartile,
  COUNT(*) AS patient_count,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS mortality_rate_pct,
  ROUND(SAFE_DIVIDE(SUM(CAST(q.cardiac_flag AS INT64)), COUNT(*)) * 100, 2) AS cardiac_comp_rate_pct,
  ROUND(SAFE_DIVIDE(SUM(CAST(q.neuro_flag AS INT64)), COUNT(*)) * 100, 2) AS neuro_comp_rate_pct,
  COALESCE(sl.median_los_survivors_days, 0) AS median_los_survivors_days
FROM quartiles q
LEFT JOIN survivor_los sl ON q.risk_quartile = sl.risk_quartile
GROUP BY q.risk_quartile, sl.median_los_survivors_days
ORDER BY q.risk_quartile;