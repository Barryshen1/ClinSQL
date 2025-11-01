WITH asthma_cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(di.long_title) LIKE '%asthma%'
    AND LOWER(di.long_title) LIKE '%exacerbation%'
),

lab_events_first_48 AS (
  SELECT 
    a.hadm_id,
    COUNT(CASE WHEN l.flag IS NOT NULL THEN 1 END) AS lab_instability_score,
    COUNT(CASE WHEN l.flag IN ('critical high', 'critical low') THEN 1 END) AS critical_lab_events
  FROM asthma_cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  WHERE 
    l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL '48' HOUR
  GROUP BY a.hadm_id
),

all_inpatients AS (
  SELECT 
    a.hadm_id,
    COUNT(CASE WHEN l.flag IN ('critical high', 'critical low') THEN 1 END) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  WHERE 
    l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL '48' HOUR
  GROUP BY a.hadm_id
),

cohort_stats AS (
  SELECT 
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY l.lab_instability_score) AS lab_instability_75th_percentile,
    AVG(l.critical_lab_events) AS avg_critical_lab_events_cohort,
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM asthma_cohort a
  LEFT JOIN lab_events_first_48 l 
    ON a.hadm_id = l.hadm_id
)

SELECT 
  cs.lab_instability_75th_percentile,
  cs.avg_critical_lab_events_cohort,
  (SELECT AVG(critical_lab_events) FROM all_inpatients) AS avg_critical_lab_events_all,
  cs.avg_los_days,
  cs.mortality_rate
FROM cohort_stats cs;