WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days (with fractional part)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J45%'  -- asthma (including exacerbations)
),
cohort_lab_counts AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS instability_score
  FROM
    cohort_admissions AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON c.hadm_id = le.hadm_id
      AND le.charttime BETWEEN c.admittime
                           AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  WHERE
    le.flag IS NOT NULL  -- captures critical/abnormal labs
  GROUP BY
    c.hadm_id
),
cohort_stats AS (
  SELECT
    -- 75th percentile instability score
    APPROX_QUANTILES(clc.instability_score, 100)[OFFSET(75)] AS cohort_p75_instability_score,
    -- mean critical labs per admission
    AVG(clc.instability_score) AS cohort_mean_instability_score,
    -- mean LOS and in-hospital mortality
    AVG(ca.los_days) AS cohort_mean_los_days,
    AVG(ca.hospital_expire_flag) AS cohort_mortality_rate
  FROM
    cohort_admissions AS ca
    LEFT JOIN cohort_lab_counts AS clc
      ON ca.hadm_id = clc.hadm_id
),
all_admissions AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
all_lab_counts AS (
  SELECT
    aa.hadm_id,
    COUNT(*) AS instability_score
  FROM
    all_admissions AS aa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON aa.hadm_id = le.hadm_id
      AND le.charttime BETWEEN aa.admittime
                           AND TIMESTAMP_ADD(aa.admittime, INTERVAL 48 HOUR)
  WHERE
    le.flag IS NOT NULL
  GROUP BY
    aa.hadm_id
),
all_stats AS (
  SELECT
    AVG(alc.instability_score) AS all_mean_instability_score
  FROM
    all_admissions AS aa
    LEFT JOIN all_lab_counts AS alc
      ON aa.hadm_id = alc.hadm_id
)
SELECT
  cs.cohort_p75_instability_score,
  cs.cohort_mean_instability_score,
  asg.all_mean_instability_score,
  cs.cohort_mean_los_days,
  cs.cohort_mortality_rate
FROM
  cohort_stats AS cs,
  all_stats AS asg;