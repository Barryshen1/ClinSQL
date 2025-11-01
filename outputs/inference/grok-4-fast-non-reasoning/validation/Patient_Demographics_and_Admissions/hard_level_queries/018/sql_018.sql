WITH cohort AS (
  -- Base cohort: female, Medicare, age 58-68 at admission, ED admission, no in-hospital death
  SELECT 
    p.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS index_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1) - INTERVAL p.anchor_age YEAR, YEAR) BETWEEN 58 AND 68
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1  -- Principal diagnosis
    AND (d.icd_code LIKE 'S72.0%' OR d.icd_code LIKE '820.%')  -- Femoral neck fracture (ICD-10/9)
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year  -- Post-anchor admissions
),
readmissions AS (
  -- Identify 30-day readmissions
  SELECT DISTINCT
    c.subject_id,
    c.index_hadm_id,
    c.index_admittime,
    c.index_dischtime,
    c.index_los,
    a2.hadm_id AS readm_hadm_id,
    a2.admittime AS readm_admittime,
    a2.dischtime AS readm_dischtime
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON c.subject_id = a2.subject_id
  WHERE 
    a2.hadm_id != c.index_hadm_id  -- Different admission
    AND a2.admittime > c.index_dischtime  -- After index discharge
    AND a2.admittime <= DATE_ADD(c.index_dischtime, INTERVAL 30 DAY)  -- Readmission starts within 30 days
    AND a2.hospital_expire_flag = 0  -- Exclude death on readmission
),
patient_outcomes AS (
  -- Aggregate to patient level
  SELECT 
    c.subject_id,
    c.index_hadm_id,
    c.index_los,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM 
    cohort c
  LEFT JOIN 
    readmissions r
    ON c.subject_id = r.subject_id AND c.index_hadm_id = r.index_hadm_id
)
-- Final metrics
SELECT 
  -- 30-day readmission rate
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN readmitted = 1 THEN subject_id END), COUNT(DISTINCT subject_id)) AS readmission_rate,
  
  -- Median index LOS by readmitted status
  (SELECT PERCENTILE_CONT(index_los, 0.5) FROM patient_outcomes WHERE readmitted = 1) AS median_los_readmitted,
  (SELECT PERCENTILE_CONT(index_los, 0.5) FROM patient_outcomes WHERE readmitted = 0) AS median_los_non_readmitted,
  
  -- Percent of initial stays >8 days
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN index_los > 8 THEN subject_id END), COUNT(DISTINCT subject_id)) * 100 AS pct_stays_over_8_days
FROM 
  patient_outcomes;