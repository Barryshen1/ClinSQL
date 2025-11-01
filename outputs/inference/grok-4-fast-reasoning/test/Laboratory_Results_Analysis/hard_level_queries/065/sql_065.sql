WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = '1'
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND (
      (d.icd_version = '9' AND d.icd_code IN ('569.3', '562.12', '569.84', '569.86')) OR
      (d.icd_version = '10' AND d.icd_code IN ('K62.5', 'K92.2'))
    )
),
general AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
cohort_scores AS (
  SELECT
    c.hadm_id,
    COUNT(CASE WHEN l.flag IN ('abnormal', 'high', 'low') THEN 1 END) AS score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
general_scores AS (
  SELECT
    g.hadm_id,
    COUNT(CASE WHEN l.flag IN ('abnormal', 'high', 'low') THEN 1 END) AS score
  FROM general g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON g.hadm_id = l.hadm_id
    AND l.charttime >= g.admittime
    AND l.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
  GROUP BY g.hadm_id
)
SELECT
  (SELECT COUNT(*) FROM cohort) AS n_cohort,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) FROM cohort) AS mean_los_days,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM cohort) AS mortality_rate,
  (SELECT APPROX_QUANTILES(score, 4 IGNORE NULLS)[OFFSET(1)] FROM cohort_scores) AS p25_lab_instability_score,
  (SELECT AVG(score) FROM cohort_scores) AS cohort_mean_critical_lab_frequency,
  (SELECT AVG(score) FROM general_scores) AS general_mean_critical_lab_frequency;