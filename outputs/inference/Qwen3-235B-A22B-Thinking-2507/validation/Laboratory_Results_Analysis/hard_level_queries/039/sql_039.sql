WITH pneumonia_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('480','481','482','483','484','485','486','4870'))
      OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'J12%' OR 
        d.icd_code LIKE 'J13%' OR 
        d.icd_code LIKE 'J14%' OR 
        d.icd_code LIKE 'J15%' OR 
        d.icd_code LIKE 'J16%' OR 
        d.icd_code LIKE 'J17%' OR 
        d.icd_code LIKE 'J18%'
      ))
    )
),

lab_scores AS (
  SELECT 
    pc.hadm_id,
    COUNT(*) AS score
  FROM pneumonia_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pc.hadm_id = l.hadm_id
  WHERE 
    l.charttime >= pc.admittime 
    AND l.charttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY pc.hadm_id
),

lab_scores_full AS (
  SELECT 
    pc.hadm_id,
    COALESCE(ls.score, 0) AS score
  FROM pneumonia_cohort pc
  LEFT JOIN lab_scores ls
    ON pc.hadm_id = ls.hadm_id
),

critical_events_cohort AS (
  SELECT 
    pc.hadm_id,
    COUNT(i.stay_id) AS icu_stay_count
  FROM pneumonia_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pc.hadm_id = i.hadm_id
  GROUP BY pc.hadm_id
),

critical_events_all AS (
  SELECT 
    a.hadm_id,
    COUNT(i.stay_id) AS icu_stay_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
)

SELECT 
  (SELECT APPROX_QUANTILES(score, 1000)[OFFSET(750)] FROM lab_scores_full) AS lab_instability_75th,
  (SELECT AVG(icu_stay_count) FROM critical_events_cohort) AS critical_event_freq_cohort,
  (SELECT AVG(icu_stay_count) FROM critical_events_all) AS critical_event_freq_all,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) FROM pneumonia_cohort) AS cohort_los,
  (SELECT AVG(hospital_expire_flag) FROM pneumonia_cohort) AS cohort_mortality
FROM 
  (SELECT 1) AS dummy;