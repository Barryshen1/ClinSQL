WITH cohort_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
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
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND dd.icd_code = 'J45.901'  -- Asthma exacerbation
    AND d.seq_num = 1  -- Primary diagnosis
),

cohort_labs AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    cohort_admissions c
  ON
    l.hadm_id = c.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (
      l.flag = 'abnormal'
      OR l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    l.hadm_id
),

cohort_stats AS (
  SELECT
    APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(75)] AS q75_critical_labs,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    cohort_admissions
  LEFT JOIN
    cohort_labs
  USING
    (hadm_id)
),

all_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

all_labs AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    all_admissions a
  ON
    l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND (
      l.flag = 'abnormal'
      OR l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    l.hadm_id
),

all_avg_critical_labs AS (
  SELECT
    AVG(critical_lab_count) AS avg_critical_labs_all
  FROM
    all_labs
)

SELECT
  c.q75_critical_labs,
  a.avg_critical_labs_all,
  c.avg_los,
  c.mortality_rate
FROM
  cohort_stats c,
  all_avg_critical_labs a;