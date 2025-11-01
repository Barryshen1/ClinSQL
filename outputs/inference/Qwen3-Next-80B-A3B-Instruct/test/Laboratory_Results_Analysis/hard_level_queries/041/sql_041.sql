WITH target_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data`.mimiciv_3_1_hosp.patients p
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND LOWER(d_icd.long_title) LIKE '%heart failure%'
),

lab_abnormal AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.admittime,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    CASE
      WHEN l.valuenum IS NOT NULL
        AND l.ref_range_lower IS NOT NULL
        AND l.ref_range_upper IS NOT NULL
        AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1
      ELSE 0
    END AS is_abnormal,
    CASE
      WHEN l.valuenum IS NOT NULL
        AND l.ref_range_lower IS NOT NULL
        AND l.ref_range_upper IS NOT NULL
        AND (l.valuenum < (l.ref_range_lower * 0.5) OR l.valuenum > (l.ref_range_upper * 2))
      THEN 1
      ELSE 0
    END AS is_critical
  FROM target_cohort t
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.labevents l
    ON t.subject_id = l.subject_id AND t.hadm_id = l.hadm_id
  INNER JOIN `physionet-data`.mimiciv_3_1_hosp.d_labitems dl
    ON l.itemid = dl.itemid
  WHERE l.charttime >= t.admittime
    AND l.charttime <= TIMESTAMP_ADD(t.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

instability_score AS (
  SELECT
    subject_id,
    COUNT(*) AS instability_score,
    SUM(is_critical) AS critical_lab_count
  FROM lab_abnormal
  GROUP BY subject_id
),

percentile_95 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_threshold
  FROM instability_score
),

grouped_patients AS (
  SELECT
    i.subject_id,
    i.instability_score,
    i.critical_lab_count,
    t.hospital_expire_flag,
    TIMESTAMP_DIFF(t.dischtime, t.admittime, SECOND) / 86400.0 AS hospital_los,
    CASE
      WHEN i.instability_score >= (SELECT p95_threshold FROM percentile_95) THEN 'high'
      ELSE 'control'
    END AS group_label
  FROM instability_score i
  INNER JOIN target_cohort t ON i.subject_id = t.subject_id
)

SELECT
  AVG(CASE WHEN group_label = 'high' THEN hospital_expire_flag ELSE NULL END) AS mortality_high,
  AVG(CASE WHEN group_label = 'high' THEN hospital_los ELSE NULL END) AS los_mean_high,
  AVG(CASE WHEN group_label = 'high' THEN CAST(critical_lab_count > 0 AS INT64) ELSE NULL END) AS critical_lab_rate_high,
  AVG(CASE WHEN group_label = 'control' THEN CAST(critical_lab_count > 0 AS INT64) ELSE NULL END) AS critical_lab_rate_control
FROM grouped_patients;