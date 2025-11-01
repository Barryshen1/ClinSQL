WITH 
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.icd_code LIKE '481%'  
),

lab_instability AS (
  SELECT 
    hadm_id,
    -- calculate laboratory instability score
    -- for simplicity, let's assume it's the difference between max and min lab values
    MAX(valuenum) - MIN(valuenum) AS lab_instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

critical_events AS (
  SELECT 
    hadm_id,
    -- count critical events
    -- for simplicity, let's assume it's the number of rows in chartevents
    COUNT(*) AS critical_event_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  GROUP BY 
    hadm_id
),

los AS (
  SELECT 
    hadm_id,
    dischtime AS hosp_dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

mortality AS (
  SELECT 
    hadm_id,
    hospital_expire_flag AS died
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_instability.lab_instability_score) AS percentile_lab_instability,
  AVG(critical_events.critical_event_count) AS mean_critical_event_count,
  AVG(TIMESTAMP_DIFF(los.hosp_dischtime, cohort.admittime, HOUR)) / 24 AS mean_los,
  SUM(CASE WHEN mortality.died = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM 
  cohort
  JOIN lab_instability ON cohort.hadm_id = lab_instability.hadm_id
  JOIN critical_events ON cohort.hadm_id = critical_events.hadm_id
  JOIN los ON cohort.hadm_id = los.hadm_id
  JOIN mortality ON cohort.hadm_id = mortality.hadm_id;