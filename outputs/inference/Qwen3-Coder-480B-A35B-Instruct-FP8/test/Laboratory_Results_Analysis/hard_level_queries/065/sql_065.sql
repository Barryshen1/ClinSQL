WITH target_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
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
    AND p.anchor_age = 70
    AND LOWER(dd.long_title) LIKE '%lower gastrointestinal hemorrhage%'
),

lab_scores AS (
  SELECT
    tc.hadm_id,
    COUNT(DISTINCT CASE
      WHEN l.flag = 'abnormal' OR
           (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN l.itemid
    END) AS instability_score
  FROM
    target_cohort tc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    tc.hadm_id = l.hadm_id
  WHERE
    l.charttime >= tc.admittime
    AND l.charttime <= DATETIME_ADD(tc.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY
    tc.hadm_id
),

general_cohort_labs AS (
  SELECT
    l.hadm_id,
    COUNT(DISTINCT CASE
      WHEN l.flag = 'abnormal' OR
           (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN l.itemid
    END) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
    AND l.hadm_id IS NOT NULL
  GROUP BY
    l.hadm_id
)

SELECT
  -- Target cohort stats
  APPROX_QUANTILES(ls.instability_score, 100)[OFFSET(25)] AS target_25th_percentile_instability,
  AVG(ls.instability_score) AS target_avg_instability,
  AVG(gc.instability_score) AS general_avg_instability,
  AVG(tc.los_days) AS avg_los_days,
  AVG(tc.hospital_expire_flag) AS mortality_rate
FROM
  target_cohort tc
LEFT JOIN
  lab_scores ls
ON
  tc.hadm_id = ls.hadm_id
CROSS JOIN
  (SELECT AVG(instability_score) AS instability_score FROM general_cohort_labs) gc;