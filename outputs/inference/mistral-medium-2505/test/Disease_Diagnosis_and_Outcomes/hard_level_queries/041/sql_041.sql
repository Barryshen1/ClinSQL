WITH
-- Define the cohort: male patients aged 68-78 with ICH post-ICU
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    t.outtime AS icu_discharge_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` t ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND t.careunit LIKE '%ICU%'
    AND t.eventtype = 'discharge'
    AND (
      (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
    )
),

-- Calculate 30-day mortality
mortality AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, icu_discharge_time, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days
  FROM
    cohort
),

-- Calculate AKI (using ICD codes)
aki AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    CASE WHEN d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END AS has_aki
  FROM
    cohort a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'N17%'
),

-- Calculate ARDS (using ICD codes)
ards AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    CASE WHEN d.icd_code LIKE 'J80%' THEN 1 ELSE 0 END AS has_ards
  FROM
    cohort a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'J80%'
),

-- Calculate composite risk score (simplified example)
risk_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Example composite score (adjust based on clinical relevance)
    (c.anchor_age * 0.5) +
    (COALESCE(a.has_aki, 0) * 10) +
    (COALESCE(ar.has_ards, 0) * 15) AS composite_score
  FROM
    cohort c
  LEFT JOIN
    aki a ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  LEFT JOIN
    ards ar ON c.subject_id = ar.subject_id AND c.hadm_id = ar.hadm_id
),

-- Calculate survival for decedents
survival AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    TIMESTAMP_DIFF(c.deathtime, c.icu_discharge_time, DAY) AS days_until_death
  FROM
    cohort c
  WHERE
    c.deathtime IS NOT NULL
)

-- Final results
SELECT
  COUNT(DISTINCT c.subject_id) AS cohort_size,
  SUM(m.died_within_30_days) / COUNT(DISTINCT c.subject_id) AS mortality_30_day_rate,
  SUM(a.has_aki) / COUNT(DISTINCT c.subject_id) AS aki_rate,
  SUM(ar.has_ards) / COUNT(DISTINCT c.subject_id) AS ards_rate,
  (
    SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] FROM risk_score
  ) AS risk_score_25th_percentile,
  (
    SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] FROM risk_score
  ) AS risk_score_50th_percentile,
  (
    SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] FROM risk_score
  ) AS risk_score_75th_percentile,
  (
    SELECT APPROX_QUANTILES(days_until_death, 100)[OFFSET(50)] FROM survival
  ) AS median_survival_days
FROM
  cohort c
LEFT JOIN
  mortality m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
LEFT JOIN
  aki a ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
LEFT JOIN
  ards ar ON c.subject_id = ar.subject_id AND c.hadm_id = ar.hadm_id;