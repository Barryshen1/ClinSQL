WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    p.gender,
    p.anchor_age,
    a.insurance,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
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
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SKILLED NURSING FACILITY'
    AND p.anchor_age BETWEEN 61 AND 71
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute kidney injury%'
    AND a.deathtime IS NULL
),

readmit_flags AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime,
    CASE
      WHEN LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) 
           BETWEEN dischtime AND DATETIME_ADD(dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS is_readmitted_30d
  FROM
    cohort
),

metrics AS (
  SELECT
    is_readmitted_30d,
    los_days,
    CASE WHEN los_days > 6 THEN 1 ELSE 0 END AS long_stay
  FROM
    readmit_flags
)

SELECT
  ROUND(AVG(is_readmitted_30d) * 100, 2) AS readmission_rate_pct,
  APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 1 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,
  ROUND(AVG(long_stay) * 100, 2) AS pct_long_stay
FROM
  metrics;