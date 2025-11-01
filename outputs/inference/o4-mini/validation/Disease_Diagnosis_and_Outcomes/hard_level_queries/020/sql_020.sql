WITH base AS (
  -- 1. Get all male inpatients age 46–56 with acute MI
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN (
      -- pick admissions with an acute MI diagnosis
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9   AND icd_code LIKE '410%')
        OR
        (icd_version = 10  AND icd_code LIKE 'I21%')
    ) mi
      USING(hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),
comp AS (
  -- 2. Count major complications per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_major_comps
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- example complication codes
    (icd_version = 9  AND icd_code IN ('78551')         -- cardiogenic shock
                      OR icd_code LIKE '428%')          -- heart failure
    OR
    (icd_version = 9  AND icd_code = '5184')             -- acute pulmonary edema
  GROUP BY
    hadm_id
),
scored AS (
  -- 3. Combine and compute risk score + binary complication flag
  SELECT
    b.*,
    COALESCE(c.num_major_comps, 0) AS num_major_comps,
    CASE WHEN COALESCE(c.num_major_comps, 0) > 0 THEN 1 ELSE 0 END AS has_complication,
    b.anchor_age + COALESCE(c.num_major_comps, 0) AS risk_score
  FROM
    base b
    LEFT JOIN comp c USING(hadm_id)
),
quintiled AS (
  -- 4. Assign risk quintile
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    scored
)
-- 5. Aggregate outcomes by quintile
SELECT
  risk_quintile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS pct_in_hospital_mortality,
  ROUND(100.0 * SUM(has_complication) / COUNT(*), 1)    AS pct_major_complication,
  -- median LOS among survivors (approximate)
  APPROX_QUANTILES(
    CASE
      WHEN hospital_expire_flag = 0
      THEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0
      ELSE NULL
    END,
    2
  )[OFFSET(1)] AS median_survivor_los_days
FROM
  quintiled
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;