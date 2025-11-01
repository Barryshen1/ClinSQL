WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE 
    d.seq_num = 1
    AND d_icd.long_title LIKE '%pneumonia%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
),

lab_scores AS (
  SELECT 
    c.subject_id, 
    COUNT(*) AS abnormal_lab_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
  WHERE 
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY c.subject_id
),

critical_events_cohort AS (
  SELECT 
    c.subject_id, 
    COUNT(ce.event) AS critical_event_count
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id, 1 AS event
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid = 223848
    UNION ALL
    SELECT hadm_id, 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (221906, 221662, 221653, 221289)
  ) ce ON c.hadm_id = ce.hadm_id
  GROUP BY c.subject_id
),

all_inpatients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),

critical_events_all AS (
  SELECT 
    ai.subject_id, 
    COUNT(ce.event) AS critical_event_count
  FROM all_inpatients ai
  LEFT JOIN (
    SELECT hadm_id, 1 AS event
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid = 223848
    UNION ALL
    SELECT hadm_id, 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (221906, 221662, 221653, 221289)
  ) ce ON ai.hadm_id = ce.hadm_id
  GROUP BY ai.subject_id
),

los_mortality AS (
  SELECT 
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort
)

SELECT 
  (SELECT APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(75)] FROM lab_scores) AS lab_score_75th_percentile,
  (SELECT AVG(critical_event_count) FROM critical_events_cohort) AS cohort_critical_event_mean,
  (SELECT AVG(critical_event_count) FROM critical_events_all) AS all_inpatients_critical_event_mean,
  avg_los_days,
  mortality_rate
FROM los_mortality;