WITH target_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

general_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

critical_lab_events AS (
  SELECT DISTINCT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    dl.label
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (
      le.flag = 'A'
      OR le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
    AND le.charttime >= a.admittime
    AND le.charttime <= a.admittime + INTERVAL '72' HOUR
),

patient_critical_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT label) AS unique_critical_lab_types
  FROM critical_lab_events
  GROUP BY subject_id, hadm_id
),

target_stats AS (
  SELECT
    MAX(pcc.unique_critical_lab_types) AS max_laboratory_instability_score,
    AVG(CASE WHEN pcc.unique_critical_lab_types >= 1 THEN 1.0 ELSE 0 END) AS critical_event_rate_target,
    AVG(TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY)) AS avg_los_days,
    AVG(CASE WHEN t.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate_target
  FROM target_cohort t
  LEFT JOIN patient_critical_counts pcc
    ON t.subject_id = pcc.subject_id AND t.hadm_id = pcc.hadm_id
),

general_stats AS (
  SELECT
    AVG(CASE WHEN pcc.unique_critical_lab_types >= 1 THEN 1.0 ELSE 0 END) AS critical_event_rate_general
  FROM general_cohort g
  LEFT JOIN patient_critical_counts pcc
    ON g.subject_id = pcc.subject_id AND g.hadm_id = pcc.hadm_id
)

SELECT
  ts.max_laboratory_instability_score,
  ts.critical_event_rate_target,
  ts.avg_los_days,
  ts.mortality_rate_target,
  gs.critical_event_rate_general
FROM target_stats ts
CROSS JOIN general_stats gs;