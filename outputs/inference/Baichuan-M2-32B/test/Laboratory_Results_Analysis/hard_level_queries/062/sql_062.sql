WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.icd_code IN ('A40', 'A41', 'R65.20')
    AND d.icd_version = 10
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.gender, p.anchor_age
),
critical_labs AS (
  SELECT
    itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    category IN ('Blood Gas', 'Chemistry', 'Hematology', 'Urinalysis')
),
first_72h_labs AS (
  SELECT
    s.hadm_id,
    COUNT(labevent_id) AS abnormal_lab_count
  FROM sepsis_admissions s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.hadm_id = l.hadm_id
    AND l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 72 HOUR)
  LEFT JOIN critical_labs cl
    ON l.itemid = cl.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY s.hadm_id
),
admission_metrics AS (
  SELECT
    s.hadm_id,
    s.hospital_expire_flag AS mortality,
    TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
    COALESCE(f.abnormal_lab_count, 0) AS instability_score
  FROM sepsis_admissions s
  LEFT JOIN first_72h_labs f
    ON s.hadm_id = f.hadm_id
)
SELECT
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25_instability_score,
  AVG(instability_score) AS mean_critical_events,
  AVG(los_days) AS mean_los,
  SUM(mortality) / COUNT(*) AS mortality_rate
FROM admission_metrics;