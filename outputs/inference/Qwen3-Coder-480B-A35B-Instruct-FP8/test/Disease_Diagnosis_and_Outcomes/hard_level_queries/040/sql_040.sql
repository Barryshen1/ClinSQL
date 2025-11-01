WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    p.anchor_age,
    p.gender,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      (d.icd_version = 9 AND d.icd_code = '431')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
    )
),

risk_score AS (
  SELECT
    hadm_id,
    anchor_age,
    icu_flag,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    deathtime,
    admittime,
    CASE
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days,
    anchor_age + (icu_flag * 10) AS composite_score
  FROM
    cohort
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS risk_quintile
  FROM
    risk_score
),

survivors AS (
  SELECT
    risk_quintile,
    los
  FROM
    quintiles
  WHERE
    died_within_30_days = 0
),

mortality_stats AS (
  SELECT
    risk_quintile,
    COUNT(*) AS n,
    AVG(died_within_30_days) * 100 AS mortality_pct
  FROM
    quintiles
  GROUP BY
    risk_quintile
),

los_stats AS (
  SELECT
    risk_quintile,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_survivor_los
  FROM
    survivors
  GROUP BY
    risk_quintile
)

SELECT
  m.risk_quintile,
  m.n,
  ROUND(m.mortality_pct, 2) AS thirty_day_mortality_pct,
  ROUND(l.median_survivor_los, 2) AS median_survivor_los
FROM
  mortality_stats m
JOIN
  los_stats l
ON
  m.risk_quintile = l.risk_quintile
ORDER BY
  m.risk_quintile;