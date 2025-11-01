WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    AND d.icd_version = 10
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

cohort_lab_events AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

general_lab_events AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    COUNT(l.labevent_id) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id
),

cohort_stats AS (
  SELECT 
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(cle.critical_lab_count, 0)) AS cohort_25th_percentile,
    AVG(COALESCE(cle.critical_lab_count, 0)) AS cohort_avg_critical_lab_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS cohort_mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS cohort_mortality_rate
  FROM cohort c
  LEFT JOIN cohort_lab_events cle 
    ON c.subject_id = cle.subject_id AND c.hadm_id = cle.hadm_id
),

general_stats AS (
  SELECT AVG(critical_lab_count) AS general_avg_critical_lab_rate
  FROM general_lab_events
)

SELECT 
  cs.cohort_25th_percentile,
  cs.cohort_avg_critical_lab_rate,
  gs.general_avg_critical_lab_rate,
  cs.cohort_mean_los_days,
  cs.cohort_mortality_rate
FROM cohort_stats cs
CROSS JOIN general_stats gs;