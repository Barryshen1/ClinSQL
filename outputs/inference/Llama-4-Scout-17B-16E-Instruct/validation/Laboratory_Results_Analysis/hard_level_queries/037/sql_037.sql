WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.hospital_expire_flag,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '430%'  -- Hemorrhagic stroke ICD code
    )
),

-- Lab events within 48 hours of admission for cohort
lab_events_48h AS (
  SELECT 
    c.hadm_id,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.valueuom
  FROM 
    cohort c
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON c.hadm_id = le.hadm_id
  WHERE 
    le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

-- Calculate lab instability score (example, actual calculation may vary)
lab_instability_score AS (
  SELECT 
    hadm_id,
    -- Example calculation: standard deviation of lab values
    STDEV(valuenum) AS instability_score
  FROM 
    lab_events_48h
  GROUP BY 
    hadm_id
),

-- General inpatient critical-lab event rate
critical_lab_events AS (
  SELECT 
    hadm_id,
    COUNT(*) AS critical_events
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    -- Define critical lab events here (e.g., specific itemids or thresholds)
    itemid IN (...)  -- Example
  GROUP BY 
    hadm_id
),

-- Length of stay calculation
admission_los AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    cohort
)

-- Final calculations
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY lis.instability_score) AS percentile_25,
  AVG(cle.critical_events) AS mean_critical_lab_events,
  AVG(al.los) AS mean_los,
  SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT c.hadm_id) AS in_hospital_mortality
FROM 
  lab_instability_score lis
  LEFT JOIN critical_lab_events cle ON lis.hadm_id = cle.hadm_id
  JOIN cohort c ON lis.hadm_id = c.hadm_id
  JOIN admission_los al ON c.hadm_id = al.hadm_id;