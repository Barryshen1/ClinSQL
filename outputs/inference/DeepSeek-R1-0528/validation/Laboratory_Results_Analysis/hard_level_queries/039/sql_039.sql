WITH pneumonia_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]')) OR
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]'))
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN pneumonia_codes pc 
    ON d.icd_code = pc.icd_code AND d.icd_version = pc.icd_version
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1  -- Primary diagnosis
),
cohort_lab AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT 
      CASE WHEN le.flag IS NOT NULL AND le.flag != 'Normal' 
      THEN le.itemid END
    ) AS lab_instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
critical_events AS (
  -- ICU stays
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  UNION ALL
  -- Mechanical ventilation procedures
  SELECT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(d.long_title, r'(?i)mechanical ventilation|ventilator')
  UNION ALL
  -- Vasopressor prescriptions
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%norepinephrine%' OR
    LOWER(drug) LIKE '%epinephrine%' OR
    LOWER(drug) LIKE '%dopamine%' OR
    LOWER(drug) LIKE '%vasopressin%' OR
    LOWER(drug) LIKE '%phenylephrine%' OR
    LOWER(drug) LIKE '%dobutamine%' OR
    LOWER(drug) LIKE '%milrinone%'
),
critical_events_per_admission AS (
  SELECT 
    hadm_id,
    COUNT(*) AS critical_event_count
  FROM critical_events
  GROUP BY hadm_id
),
all_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort_with_events AS (
  SELECT 
    c.*,
    COALESCE(cl.lab_instability_score, 0) AS lab_instability_score,
    COALESCE(ce.critical_event_count, 0) AS critical_event_count
  FROM cohort c
  LEFT JOIN cohort_lab cl ON c.hadm_id = cl.hadm_id
  LEFT JOIN critical_events_per_admission ce ON c.hadm_id = ce.hadm_id
),
all_inpatients_with_events AS (
  SELECT 
    a.hadm_id,
    COALESCE(ce.critical_event_count, 0) AS critical_event_count
  FROM all_admissions a
  LEFT JOIN critical_events_per_admission ce ON a.hadm_id = ce.hadm_id
)
SELECT
  -- 75th percentile of lab instability score
  (SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] 
   FROM cohort_with_events) AS lab_instability_75th_percentile,
  -- Mean critical events for cohort
  (SELECT AVG(critical_event_count) 
   FROM cohort_with_events) AS cohort_mean_critical_events,
  -- Mean critical events for all inpatients
  (SELECT AVG(critical_event_count) 
   FROM all_inpatients_with_events) AS all_inpatients_mean_critical_events,
  -- Cohort mean length of stay (days)
  (SELECT AVG(DATETIME_DIFF(dischtime, admittime, DAY)) 
   FROM cohort) AS cohort_mean_los,
  -- Cohort mortality rate (%)
  (SELECT AVG(hospital_expire_flag) * 100 
   FROM cohort) AS cohort_mortality_rate;