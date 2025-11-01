WITH cohort AS (
  -- Base cohort: female, 89-99, septic shock (primary dx), with ICU stay
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND d.seq_num = 1  -- Primary diagnosis
    AND (d.icd_code = '785.52' OR d.icd_code = 'R65.21')  -- Septic shock codes
    AND icu.stay_id = (
      SELECT MIN(stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays` icu2
      WHERE icu2.subject_id = icu.subject_id AND icu2.hadm_id = icu.hadm_id
    )  -- First ICU stay per admission
),

general_inpatients AS (
  -- General: all female 89-99 inpatients (no septic shock filter)
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),

qsofa_components AS (
  -- Extract vitals for qSOFA in first 48h of ICU (latest per hour to reduce noise)
  SELECT c.stay_id,
         MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum <= 100 THEN 1 ELSE 0 END) AS has_low_sbp,  -- SBP <=100
         MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum >= 22 THEN 1 ELSE 0 END) AS has_high_rr,   -- RR >=22
         MAX(CASE WHEN ce.itemid = 220739 AND ce.valuenum <= 14 THEN 1 ELSE 0 END) AS has_low_gcs    -- GCS <=14 (total)
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 220210, 220739)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id, EXTRACT(HOUR FROM ce.charttime)  -- Hourly max
),

qsofa_scores AS (
  -- Compute max qSOFA per stay (sum points, max over time)
  SELECT c.stay_id,
         MAX( (COALESCE(qc.has_low_sbp, 0) + COALESCE(qc.has_high_rr, 0) + COALESCE(qc.has_low_gcs, 0)) ) AS max_qsofa
  FROM cohort c
  LEFT JOIN qsofa_components qc ON c.stay_id = qc.stay_id
  GROUP BY c.stay_id
),

abnormal_labs_cohort AS (
  -- Abnormal labs in first 48h of admission (key sepsis labs)
  SELECT c.subject_id,
         COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND le.itemid IN (26464, 50882, 50912, 50885) THEN le.itemid END) AS num_abnormal_lab_types
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  WHERE le.itemid IN (26464, 50882, 50912, 50885)  -- WBC, lactate, creatinine, bilirubin
    AND le.flag = 'abnormal'
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id
),

abnormal_labs_general AS (
  -- Same for general
  SELECT g.subject_id,
         COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' AND le.itemid IN (26464, 50882, 50912, 50885) THEN le.itemid END) AS num_abnormal_lab_types
  FROM general_inpatients g
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON g.subject_id = le.subject_id AND g.hadm_id = le.hadm_id
  WHERE le.itemid IN (26464, 50882, 50912, 50885)
    AND le.flag = 'abnormal'
    AND le.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  GROUP BY g.subject_id
),

cohort_stats AS (
  SELECT 
    'Septic Shock Cohort' AS group_name,
    COUNT(DISTINCT c.subject_id) AS n_patients,
    -- qSOFA stats (max in first 48h)
    APPROX_QUANTILES(qs.max_qsofa, 4)[OFFSET(1)] AS qsofa_q1,
    APPROX_QUANTILES(qs.max_qsofa, 4)[OFFSET(2)] AS qsofa_median,
    APPROX_QUANTILES(qs.max_qsofa, 4)[OFFSET(3)] AS qsofa_q3,
    (APPROX_QUANTILES(qs.max_qsofa, 4)[OFFSET(3)] - APPROX_QUANTILES(qs.max_qsofa, 4)[OFFSET(1)]) AS qsofa_iqr,
    -- LOS (days, avg; use deathtime if expired)
    AVG(EXTRACT(DAY FROM COALESCE(a.dischtime, a.deathtime) - a.admittime) + 
        EXTRACT(HOUR FROM COALESCE(a.dischtime, a.deathtime) - a.admittime)/24.0) AS avg_los_days,
    -- Mortality
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(DISTINCT c.subject_id) AS mortality_rate,
    -- Abnormal lab freq (% patients with >=1 abnormal key lab)
    COUNT(DISTINCT CASE WHEN al.num_abnormal_lab_types >= 1 THEN c.subject_id END) * 1.0 / COUNT(DISTINCT c.subject_id) AS pct_with_abnormal_labs
  FROM cohort c
  LEFT JOIN qsofa_scores qs ON c.stay_id = qs.stay_id
  LEFT JOIN abnormal_labs_cohort al ON c.subject_id = al.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id  -- Rejoin for deathtime if needed
  GROUP BY 1
),

general_stats AS (
  SELECT 
    'General Inpatients' AS group_name,
    COUNT(DISTINCT g.subject_id) AS n_patients,
    NULL AS qsofa_q1, NULL AS qsofa_median, NULL AS qsofa_q3, NULL AS qsofa_iqr,  -- Not computed for general
    AVG(EXTRACT(DAY FROM COALESCE(a.dischtime, a.deathtime) - a.admittime) + 
        EXTRACT(HOUR FROM COALESCE(a.dischtime, a.deathtime) - a.admittime)/24.0) AS avg_los_days,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(DISTINCT g.subject_id) AS mortality_rate,
    COUNT(DISTINCT CASE WHEN al.num_abnormal_lab_types >= 1 THEN g.subject_id END) * 1.0 / COUNT(DISTINCT g.subject_id) AS pct_with_abnormal_labs
  FROM general_inpatients g
  LEFT JOIN abnormal_labs_general al ON g.subject_id = al.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON g.hadm_id = a.hadm_id
  GROUP BY 1
)

SELECT * FROM cohort_stats
UNION ALL
SELECT * FROM general_stats
ORDER BY group_name;