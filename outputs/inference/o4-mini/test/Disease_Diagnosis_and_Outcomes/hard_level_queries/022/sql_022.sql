WITH
-- 1. Base admissions with patient info
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.anchor_age BETWEEN 40 AND 50
    AND p.gender = 'F'
),
-- 2. Flag AKI and ARDS diagnoses
dx_flags AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%acute kidney injury%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%acute respiratory distress syndrome%' THEN 1 ELSE 0 END) AS has_ards,
    COUNT(DISTINCT IF(
      LOWER(d.long_title) NOT LIKE '%acute kidney injury%'
      AND LOWER(d.long_title) NOT LIKE '%acute respiratory distress syndrome%',
      di.icd_code,
      NULL
    )) AS comorb_count
  FROM
    base b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  GROUP BY
    b.subject_id,
    b.hadm_id
  HAVING
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%acute kidney injury%' THEN 1 ELSE 0 END) = 1
),
-- 3. Combine and compute risk, LOS, mortality
with_risk AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag,
    f.has_ards,
    f.comorb_count,
    -- Composite risk score
    5 * f.comorb_count + 50 * f.has_ards AS composite_risk,
    -- Length of stay in days
    TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) AS los_days,
    -- 30-day post-discharge mortality
    CASE
      WHEN b.hospital_expire_flag = 0
        AND b.deathtime IS NOT NULL
        AND b.deathtime > b.dischtime
        AND b.deathtime <= TIMESTAMP_ADD(b.dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS mortality_30
  FROM
    base b
    JOIN dx_flags f
      USING(subject_id, hadm_id)
),
-- 4. Assign quintiles
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_risk) AS risk_quintile
  FROM
    with_risk
)
-- 5. Aggregate per quintile
SELECT
  risk_quintile,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(mortality_30) / COUNT(*), 1) AS pct_30d_post_mortality,
  ROUND(100.0 * SUM(has_ards) / COUNT(*), 1)     AS pct_ards,
  -- Median LOS among survivors (in-hospital & 30-day survivors)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los_days
FROM
  quintiled
WHERE
  hospital_expire_flag = 0
  AND mortality_30 = 0
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;