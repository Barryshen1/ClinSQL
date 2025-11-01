WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 87 AND 97
),

lab_events_72h AS (
  SELECT
    pa.hadm_id,
    COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS instability_score
  FROM patient_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON pa.hadm_id = le.hadm_id
    AND le.charttime >= pa.admittime
    AND le.charttime < DATETIME_ADD(pa.admittime, INTERVAL 72 HOUR)
  GROUP BY pa.hadm_id
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(950)] AS p95_score
  FROM lab_events_72h
),

general_inpatients AS (
  SELECT
    pa.hadm_id,
    COUNT(CASE WHEN le.flag IN ('abnormal', 'delta', 'high', 'low') THEN 1 END) AS critical_lab_count
  FROM patient_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON pa.hadm_id = le.hadm_id
  GROUP BY pa.hadm_id
),

high_instability_patients AS (
  SELECT
    pa.hadm_id,
    pa.dischtime,
    pa.admittime,
    pa.hospital_expire_flag,
    COALESCE(lev.instability_score, 0) AS instability_score
  FROM patient_admissions pa
  INNER JOIN lab_events_72h lev ON pa.hadm_id = lev.hadm_id
  CROSS JOIN percentiles p
  WHERE lev.instability_score >= p.p95_score
),

summary_high AS (
  SELECT
    AVG(TIMESTAMP_DIFF(h.dischtime, h.admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(h.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    AVG(gi.critical_lab_count) AS avg_critical_labs_per_patient
  FROM high_instability_patients h
  INNER JOIN general_inpatients gi ON h.hadm_id = gi.hadm_id
),

summary_general AS (
  SELECT
    AVG(critical_lab_count) AS avg_critical_labs_general
  FROM general_inpatients
)

SELECT
  s1.mean_los_days,
  s1.in_hospital_mortality_rate,
  s1.avg_critical_labs_per_patient,
  s2.avg_critical_labs_general
FROM summary_high s1
CROSS JOIN summary_general s2;