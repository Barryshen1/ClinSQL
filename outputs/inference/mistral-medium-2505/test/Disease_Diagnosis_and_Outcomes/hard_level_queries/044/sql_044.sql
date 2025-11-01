WITH
-- Female patients aged 59-69
female_59_69 AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
),

-- Cardiac arrest admissions (using ICD-9/10 codes for cardiac arrest)
cardiac_arrest_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT d.icd_code) AS num_comorbidities
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_59_69)
    AND (
      d.icd_code LIKE '427.5%'  -- ICD-9 for cardiac arrest
      OR d.icd_code LIKE 'I46%'   -- ICD-10 for cardiac arrest
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),

-- Risk score quartiles (using number of comorbidities as proxy)
risk_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    num_comorbidities,
    NTILE(4) OVER (ORDER BY num_comorbidities) AS risk_quartile
  FROM
    cardiac_arrest_admissions
),

-- 30-day mortality (death within 30 days of admission)
mortality_30d AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.risk_quartile,
    CASE
      WHEN r.deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(r.deathtime, r.admittime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS died_within_30d
  FROM
    risk_quartiles r
),

-- Cardiovascular complications (e.g., AMI, stroke)
complications AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.risk_quartile,
    MAX(CASE WHEN d.icd_code LIKE 'I21%' THEN 1 ELSE 0 END) AS has_cardiovascular_complication,
    MAX(CASE WHEN d.icd_code LIKE 'I63%' THEN 1 ELSE 0 END) AS has_neurologic_complication
  FROM
    risk_quartiles r
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON r.subject_id = d.subject_id AND r.hadm_id = d.hadm_id
  GROUP BY
    r.subject_id, r.hadm_id, r.risk_quartile
),

-- LOS for survivors
los_survivors AS (
  SELECT
    r.risk_quartile,
    PERCENTILE_CONT(DATE_DIFF(r.dischtime, r.admittime, DAY), 0.5) OVER (PARTITION BY r.risk_quartile) AS median_los
  FROM
    risk_quartiles r
  WHERE
    r.deathtime IS NULL OR TIMESTAMP_DIFF(r.deathtime, r.admittime, DAY) > 30
),

-- Baseline 30-day mortality for all female 59-69
baseline_mortality AS (
  SELECT
    COUNT(DISTINCT CASE
      WHEN a.deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30
      THEN a.subject_id
    END) AS num_dead_30d,
    COUNT(DISTINCT a.subject_id) AS total_patients,
    COUNT(DISTINCT CASE
      WHEN a.deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30
      THEN a.subject_id
    END) / COUNT(DISTINCT a.subject_id) AS mortality_rate_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_59_69 f ON a.subject_id = f.subject_id
)

-- Final results
SELECT
  rq.risk_quartile,
  COUNT(DISTINCT rq.subject_id) AS num_patients,
  SUM(m.died_within_30d) / COUNT(DISTINCT rq.subject_id) AS mortality_30d,
  SUM(c.has_cardiovascular_complication) / COUNT(DISTINCT rq.subject_id) AS cardiovascular_complication_rate,
  SUM(c.has_neurologic_complication) / COUNT(DISTINCT rq.subject_id) AS neurologic_complication_rate,
  MAX(ls.median_los) AS median_los_survivors,
  b.mortality_rate_30d AS baseline_mortality_30d
FROM
  risk_quartiles rq
JOIN
  mortality_30d m ON rq.subject_id = m.subject_id AND rq.hadm_id = m.hadm_id
JOIN
  complications c ON rq.subject_id = c.subject_id AND rq.hadm_id = c.hadm_id
JOIN
  los_survivors ls ON rq.risk_quartile = ls.risk_quartile
CROSS JOIN
  baseline_mortality b
GROUP BY
  rq.risk_quartile, b.mortality_rate_30d
ORDER BY
  rq.risk_quartile;