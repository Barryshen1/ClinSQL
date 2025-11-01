WITH stroke_cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('434.01','434.11','434.91','436'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63.%')
    )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
),
lab_events_72h AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE 
    le.flag IN ('H','L','A')
    AND le.charttime BETWEEN le.admittime AND TIMESTAMP_ADD(le.admittime, INTERVAL 72 HOUR)
    AND le.hadm_id IS NOT NULL
    AND le.charttime IS NOT NULL
  GROUP BY le.hadm_id
),
cohort_with_labs AS (
  SELECT
    s.*,
    COALESCE(l.critical_lab_count, 0) AS instability_score
  FROM stroke_cohort s
  LEFT JOIN lab_events_72h l
    ON s.hadm_id = l.hadm_id
),
general_inpatients AS (
  SELECT
    a.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.flag IN ('H','L','A')
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.charttime IS NOT NULL
  WHERE 
    a.hadm_id NOT IN (SELECT hadm_id FROM stroke_cohort)
    AND a.admittime IS NOT NULL
  GROUP BY a.hadm_id
),
general_avg AS (
  SELECT
    AVG(critical_lab_count) AS avg_instability_score_general
  FROM general_inpatients
),
cohort_stats AS (
  SELECT
    MIN(instability_score) AS min_instability_score,
    AVG(instability_score) AS avg_instability_score_cohort,
    AVG(los_days) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort_with_labs
)
SELECT
  c.*,
  g.avg_instability_score_general
FROM cohort_stats c
CROSS JOIN general_avg g;