WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
aki_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.dod,
    c.age_at_admission
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  WHERE 
    c.age_at_admission BETWEEN 40 AND 50
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('584', '5845', '5846', '5847', '5848', '5849'))
      OR (di.icd_version = 10 AND di.icd_code IN ('N17', 'N170', 'N171', 'N172', 'N178', 'N179'))
    )
),
comorb_ards AS (
  SELECT
    aki.hadm_id,
    -- Flag ARDS (1 if present, else 0)
    MAX(CASE 
          WHEN (di.icd_version = 9 AND di.icd_code = '51882') 
             OR (di.icd_version = 10 AND di.icd_code = 'J80') 
          THEN 1 ELSE 0 
        END) AS ards_flag,
    -- Count distinct comorbidities (exclude AKI/ARDS codes)
    COUNT(DISTINCT 
          CASE WHEN (di.icd_version = 9 AND di.icd_code IN ('584','5845','5846','5847','5848','5849','51882')) 
                OR (di.icd_version = 10 AND di.icd_code IN ('N17','N170','N171','N172','N178','N179','J80'))
               THEN NULL  -- Exclude AKI/ARDS
               ELSE CONCAT(di.icd_code, '_', CAST(di.icd_version AS STRING))
          END
    ) AS comorbidity_count
  FROM aki_admissions aki
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON aki.hadm_id = di.hadm_id
  GROUP BY aki.hadm_id
),
risk_data AS (
  SELECT
    aki.*,
    ca.ards_flag,
    ca.comorbidity_count,
    -- Calculate risk score: 5*comorbidities + 50 if ARDS
    (5 * ca.comorbidity_count) + (CASE WHEN ca.ards_flag = 1 THEN 50 ELSE 0 END) AS risk_score
  FROM aki_admissions aki
  INNER JOIN comorb_ards ca
    ON aki.hadm_id = ca.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM risk_data
),
outcomes AS (
  SELECT
    risk_quintile,
    hadm_id,
    -- 30-day post-discharge mortality (0/1)
    CASE
      WHEN hospital_expire_flag = 1 THEN 0  -- Exclude in-hospital deaths
      WHEN dod IS NOT NULL AND dod <= DATE_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS mortality_30d,
    ards_flag,
    -- LOS for survivors (NULL if died in hospital)
    CASE
      WHEN hospital_expire_flag = 0 
        THEN DATE_DIFF(dischtime, admittime, DAY)
      ELSE NULL
    END AS los_days
  FROM quintiles
)
SELECT
  risk_quintile,
  COUNT(hadm_id) AS N,
  ROUND(AVG(mortality_30d) * 100, 2) AS mortality_30d_pct,
  ROUND(AVG(ards_flag) * 100, 2) AS ards_cooccurrence_pct,
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(50)] AS median_survivor_los_days
FROM outcomes
GROUP BY risk_quintile
ORDER BY risk_quintile;