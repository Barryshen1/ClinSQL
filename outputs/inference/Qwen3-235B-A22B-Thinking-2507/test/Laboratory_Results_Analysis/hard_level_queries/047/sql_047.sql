WITH admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
ards_cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.age_at_admit
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.icd_code = 'J80' 
    AND d.icd_version = 10
    AND a.gender = 'M'
    AND a.age_at_admit BETWEEN 71 AND 81
),
instability_scores AS (
  SELECT 
    a.hadm_id,
    COUNT(l.labevent_id) AS instability_score
  FROM ards_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY a.hadm_id
),
threshold AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(900)] AS p90_instability
  FROM instability_scores
),
high_instability_patients AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.age_at_admit,
    i.instability_score
  FROM ards_cohort a
  INNER JOIN instability_scores i
    ON a.hadm_id = i.hadm_id
  CROSS JOIN threshold t
  WHERE i.instability_score >= t.p90_instability
),
high_instability_metrics AS (
  SELECT 
    h.hadm_id,
    h.hospital_expire_flag,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
     WHERE l.hadm_id = h.hadm_id 
       AND l.charttime >= h.admittime 
       AND l.charttime <= h.dischtime 
       AND l.flag = 'abnormal') AS total_abnormal_labs
  FROM high_instability_patients h
),
general_inpatients_metrics AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
     WHERE l.hadm_id = a.hadm_id 
       AND l.charttime >= a.admittime 
       AND l.charttime <= a.dischtime 
       AND l.flag = 'abnormal') AS total_abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
)
SELECT 
  (SELECT p90_instability FROM threshold) AS p90_instability,
  AVG(h.hospital_expire_flag) AS mortality_rate,
  AVG(h.los_days) AS mean_los_days,
  SUM(h.total_abnormal_labs) / NULLIF(SUM(h.los_days), 0) AS critical_lab_rate_group,
  (SELECT SUM(total_abnormal_labs) / NULLIF(SUM(los_days), 0)
   FROM general_inpatients_metrics) AS critical_lab_rate_general
FROM high_instability_metrics h
WHERE h.los_days > 0;