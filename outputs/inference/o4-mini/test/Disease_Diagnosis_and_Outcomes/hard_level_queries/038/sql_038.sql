WITH
-- 1. Base set of male inpatients age 74-84
general AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 74 AND 84
    AND p.gender = 'M'
),
-- 2. Mark AKI admissions
aki_flags AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN icd_version = 9  AND icd_code LIKE '584%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'N17%' THEN 1
      ELSE 0
    END) AS has_aki
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
-- 3. Mark ARDS admissions
ards_flags AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN icd_version = 9  AND icd_code = '51882' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'J80%' THEN 1
      ELSE 0
    END) AS has_ards
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
-- 4. General (non-AKI) cohort
gen_cohort AS (
  SELECT
    g.*,
    af.has_aki,
    rf.has_ards,
    DATE_DIFF(g.dischtime, g.admittime, DAY) AS los_days,
    CASE
      WHEN g.deathtime IS NOT NULL
           AND DATE_DIFF(g.deathtime, g.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30d
  FROM
    general AS g
    LEFT JOIN aki_flags AS af USING(hadm_id)
    LEFT JOIN ards_flags AS rf USING(hadm_id)
  WHERE
    af.has_aki = 0
),
-- 5. AKI cohort
aki_cohort AS (
  SELECT
    g.*,
    rf.has_ards,
    DATE_DIFF(g.dischtime, g.admittime, DAY) AS los_days,
    CASE
      WHEN g.deathtime IS NOT NULL
           AND DATE_DIFF(g.deathtime, g.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30d
  FROM
    general AS g
    JOIN aki_flags AS af USING(hadm_id)
    LEFT JOIN ards_flags AS rf USING(hadm_id)
  WHERE
    af.has_aki = 1
)
-- Final comparison
SELECT
  'AKI Cohort' AS cohort,
  ROUND(100.0 * SUM(died_within_30d) / COUNT(*), 1) AS thirty_day_mortality_pct,
  ROUND(100.0 * SUM(has_ards)        / COUNT(*), 1) AS ards_pct,
  -- Extract 25th, 50th, and 75th percentiles of LOS among survivors
  q[OFFSET(250)] AS los_q1_days,
  q[OFFSET(500)] AS los_median_days,
  q[OFFSET(750)] AS los_q3_days
FROM (
  SELECT
    died_within_30d,
    los_days,
    APPROX_QUANTILES(IF(died_within_30d = 0, los_days, NULL), 1001) AS q
  FROM
    aki_cohort
)
UNION ALL
SELECT
  'General Cohort' AS cohort,
  ROUND(100.0 * SUM(died_within_30d) / COUNT(*), 1) AS thirty_day_mortality_pct,
  ROUND(100.0 * SUM(has_ards)        / COUNT(*), 1) AS ards_pct,
  q[OFFSET(250)] AS los_q1_days,
  q[OFFSET(500)] AS los_median_days,
  q[OFFSET(750)] AS los_q3_days
FROM (
  SELECT
    died_within_30d,
    los_days,
    APPROX_QUANTILES(IF(died_within_30d = 0, los_days, NULL), 1001) AS q
  FROM
    gen_cohort
);