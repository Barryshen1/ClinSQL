WITH stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code IN ('43401', '43411', '43491'))
     OR (icd_version = 10 AND icd_code LIKE 'I63%')
),
cohort_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN stroke_codes sc
    ON diag.icd_code = sc.icd_code AND diag.icd_version = sc.icd_version
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 78 AND 88
  GROUP BY adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),
cohort_lab AS (
  SELECT 
    ca.hadm_id,
    COUNT(le.labevent_id) AS critical_count
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.hadm_id = le.hadm_id
    AND le.charttime <= TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
    AND le.flag IN ('abnormal', 'high', 'low')
  GROUP BY ca.hadm_id
),
cohort_summary AS (
  SELECT 
    MIN(cl.critical_count) AS min_lab_instability_score,
    AVG(cl.critical_count) AS cohort_avg_critical_lab_events,
    AVG(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0) AS cohort_avg_los,
    AVG(ca.hospital_expire_flag) AS cohort_mortality_rate
  FROM cohort_admissions ca
  LEFT JOIN cohort_lab cl ON ca.hadm_id = cl.hadm_id
),
general_lab AS (
  SELECT 
    adm.hadm_id,
    COUNT(le.labevent_id) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime <= TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND le.flag IN ('abnormal', 'high', 'low')
  GROUP BY adm.hadm_id
),
general_summary AS (
  SELECT 
    AVG(critical_count) AS general_avg_critical_lab_events
  FROM general_lab
)
SELECT 
  cs.min_lab_instability_score,
  cs.cohort_avg_critical_lab_events,
  gs.general_avg_critical_lab_events,
  cs.cohort_avg_los,
  cs.cohort_mortality_rate
FROM cohort_summary cs, general_summary gs;