WITH population AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.dod,
    -- Calculate age at admission using MIMIC-IV standard approach
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 40 AND 50
    -- Filter for patients with AKI using standard ICD codes
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '584%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
),

aki_ards_data AS (
  SELECT 
    p.*,
    -- Count comorbidities (distinct diagnoses excluding AKI and ARDS)
    (SELECT COUNT(DISTINCT icd_code)
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.hadm_id = p.hadm_id
       AND NOT (
         (d.icd_version = 9 AND d.icd_code LIKE '584%')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
       )
       AND NOT (
         (d.icd_version = 9 AND d.icd_code = '51881')
         OR (d.icd_version = 10 AND d.icd_code = 'J80')
       )
    ) AS comorbidity_count,
    -- Check for ARDS presence
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = p.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '51881')
          OR (d.icd_version = 10 AND d.icd_code = 'J80')
        )
    ) AS has_ards
  FROM population p
),

risk_scores AS (
  SELECT 
    *,
    5 * comorbidity_count + IF(has_ards, 50, 0) AS risk_score
  FROM aki_ards_data
),

metrics AS (
  SELECT 
    *,
    -- 30-day post-discharge mortality flag
    CASE 
      WHEN hospital_expire_flag = 0 
        AND dod IS NOT NULL 
        AND dod > dischtime 
        AND dod <= dischtime + INTERVAL '30' DAY 
      THEN 1 
      ELSE 0 
    END AS died_30d,
    -- LOS in days (for median calculation)
    DATETIME_DIFF(CAST(dischtime AS DATETIME), CAST(admittime AS DATETIME), DAY) AS los_days
  FROM risk_scores
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM metrics
)

SELECT
  risk_quintile,
  COUNT(*) AS N,
  -- 30-day post-discharge mortality %
  ROUND(100.0 * SUM(died_30d) / COUNT(*), 2) AS mortality_30d_pct,
  -- ARDS co-occurrence %
  ROUND(100.0 * SUM(CASE WHEN has_ards THEN 1 ELSE 0 END) / COUNT(*), 2) AS ards_pct,
  -- Median survivor LOS (days) - only for discharged alive patients
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, los_days, NULL), 100)[OFFSET(50)] AS median_survivor_los
FROM quintiles
GROUP BY risk_quintile
ORDER BY risk_quintile;