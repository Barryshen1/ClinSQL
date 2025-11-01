WITH
-- 1. Female inpatients aged 50-60
female_50_60 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

-- 2. Admissions with HHS diagnosis
hhs_icd_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    REGEXP_CONTAINS(icd_code, r'^E(08|09|10|11|13)\.(0|1)$')
),
hhs_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN hhs_icd_codes icd
      ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
),

-- 3. Cohort: Female 50-60 with HHS
cohort AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.hospital_expire_flag
  FROM
    female_50_60 f
    JOIN hhs_admissions h
      ON f.subject_id = h.subject_id AND f.hadm_id = h.hadm_id
),

-- 4. Lab instability score for cohort (first 48h)
cohort_lab_instability AS (
  SELECT
    c.hadm_id,
    COUNTIF(l.flag = 'abnormal') AS instability_score,
    COUNT(*) AS total_labs
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON c.hadm_id = l.hadm_id
      AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    c.hadm_id
),

-- 5. 75th percentile of instability score
percentile_75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[SAFE_OFFSET(75)] AS instability_75th
  FROM
    cohort_lab_instability
),

-- 6. Admissions above threshold
high_instability_admissions AS (
  SELECT
    c.*,
    cli.instability_score,
    cli.total_labs
  FROM
    cohort c
    JOIN cohort_lab_instability cli
      ON c.hadm_id = cli.hadm_id
    CROSS JOIN percentile_75 p
  WHERE
    cli.instability_score >= p.instability_75th
),

-- 7. Outcomes for high-instability admissions
high_instability_outcomes AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND)/86400.0) AS mean_los_days,
    SUM(cli.instability_score) AS total_abnormal_labs,
    SUM(cli.total_labs) AS total_labs,
    SAFE_DIVIDE(SUM(cli.instability_score), SUM(cli.total_labs)) AS critical_lab_rate
  FROM
    high_instability_admissions cli
),

-- 8. General inpatient critical-lab rate (first 48h)
general_lab_instability AS (
  SELECT
    a.hadm_id,
    COUNTIF(l.flag = 'abnormal') AS instability_score,
    COUNT(*) AS total_labs
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.hadm_id
),
general_lab_rate AS (
  SELECT
    SUM(instability_score) AS total_abnormal_labs,
    SUM(total_labs) AS total_labs,
    SAFE_DIVIDE(SUM(instability_score), SUM(total_labs)) AS critical_lab_rate
  FROM
    general_lab_instability
)

-- Final output
SELECT
  p.instability_75th AS instability_score_75th_percentile,
  o.n_admissions AS admissions_above_threshold,
  o.n_deaths AS deaths_above_threshold,
  SAFE_DIVIDE(o.n_deaths, o.n_admissions) AS mortality_rate,
  o.mean_los_days,
  o.critical_lab_rate AS critical_lab_rate_high_instability,
  g.critical_lab_rate AS critical_lab_rate_general_inpatients
FROM
  percentile_75 p,
  high_instability_outcomes o,
  general_lab_rate g;