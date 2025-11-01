WITH aki_codes AS (
  -- AKI ICD codes: N17 (ICD-9), N17.x (ICD-10)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '584%') -- ICD-9 AKI
     OR (icd_version = 10 AND icd_code LIKE 'N17%') -- ICD-10 AKI
),
ards_codes AS (
  -- ARDS ICD codes: 518.82 (ICD-9), J80 (ICD-10)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code = '51882')
     OR (icd_version = 10 AND icd_code = 'J80')
),
aki_admissions AS (
  -- Female, age 40-50, with AKI diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN aki_codes ak
    ON d.icd_code = ak.icd_code AND d.icd_version = ak.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
comorbidities AS (
  -- Count unique comorbidities per admission (excluding AKI)
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM aki_codes ak
        WHERE d.icd_code = ak.icd_code AND d.icd_version = ak.icd_version
      ) THEN d.icd_code
      ELSE NULL
    END) AS comorbidity_count
  FROM aki_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
ards_flag AS (
  -- Flag ARDS co-occurrence per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    MAX(CASE
      WHEN EXISTS (
        SELECT 1 FROM ards_codes ar
        WHERE d.icd_code = ar.icd_code AND d.icd_version = ar.icd_version
      ) THEN 1 ELSE 0 END
    ) AS has_ards
  FROM aki_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
aki_cohort AS (
  -- Combine all features per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.gender,
    a.admittime,
    a.dischtime,
    a.dod,
    c.comorbidity_count,
    ar.has_ards,
    -- Composite risk score
    5 * c.comorbidity_count + 50 * ar.has_ards AS risk,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400) AS los_days,
    -- 30-day post-discharge mortality
    CASE
      WHEN a.dod IS NOT NULL AND TIMESTAMP_DIFF(a.dod, a.dischtime, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS died_30d_post_discharge,
    -- Survivor flag (alive at least 30 days post-discharge)
    CASE
      WHEN a.dod IS NULL OR TIMESTAMP_DIFF(a.dod, a.dischtime, DAY) > 30 THEN 1
      ELSE 0
    END AS survivor_30d
  FROM aki_admissions a
  LEFT JOIN comorbidities c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  LEFT JOIN ards_flag ar
    ON a.subject_id = ar.subject_id AND a.hadm_id = ar.hadm_id
),
aki_quintiles AS (
  -- Assign quintile based on composite risk
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk) AS risk_quintile
  FROM aki_cohort
),
median_survivor_los AS (
  -- Compute median LOS among survivors per risk_quintile
  SELECT
    risk_quintile,
    ROUND(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY risk_quintile), 2) AS median_survivor_los_days
  FROM aki_quintiles
  WHERE survivor_30d = 1
)
SELECT
  q.risk_quintile,
  COUNT(*) AS N,
  ROUND(100 * SUM(q.died_30d_post_discharge) / COUNT(*), 2) AS mortality_30d_pct,
  ROUND(100 * SUM(q.has_ards) / COUNT(*), 2) AS ards_pct,
  -- Take distinct median value per quintile
  MAX(m.median_survivor_los_days) AS median_survivor_los_days
FROM aki_quintiles q
LEFT JOIN (
  SELECT DISTINCT risk_quintile, median_survivor_los_days
  FROM median_survivor_los
) m
  ON q.risk_quintile = m.risk_quintile
GROUP BY q.risk_quintile
ORDER BY q.risk_quintile;