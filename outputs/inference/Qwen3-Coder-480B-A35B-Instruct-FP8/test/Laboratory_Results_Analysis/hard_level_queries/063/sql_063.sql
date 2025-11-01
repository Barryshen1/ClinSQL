WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '415.1%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I26.%')
    )
),

lab_scores AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    c.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (
      le.flag = 'abnormal'
      OR le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
  GROUP BY
    c.hadm_id
),

threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS score_threshold
  FROM
    lab_scores
),

patients_above_threshold AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    lab_scores ls ON c.hadm_id = ls.hadm_id
  CROSS JOIN
    threshold t
  WHERE
    ls.instability_score >= t.score_threshold
),

mortality_los AS (
  SELECT
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS mortality_percent,
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los_days
  FROM
    patients_above_threshold
),

critical_labs_above AS (
  SELECT
    COUNTIF(
      le.flag = 'abnormal'
      OR (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    ) AS abnormal_count,
    COUNT(*) AS total_count
  FROM
    patients_above_threshold c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    c.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

critical_labs_all AS (
  SELECT
    COUNTIF(
      le.flag = 'abnormal'
      OR (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    ) AS abnormal_count,
    COUNT(*) AS total_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    a.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
)

SELECT
  (SELECT score_threshold FROM threshold) AS score_threshold_75th_percentile,
  m.mortality_percent,
  m.mean_los_days,
  SAFE_DIVIDE((SELECT abnormal_count FROM critical_labs_above), (SELECT total_count FROM critical_labs_above)) AS critical_lab_rate_in_high_risk,
  SAFE_DIVIDE((SELECT abnormal_count FROM critical_labs_all), (SELECT total_count FROM critical_labs_all)) AS critical_lab_rate_all_inpatients
FROM
  mortality_los m;