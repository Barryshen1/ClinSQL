WITH 
-- Identify cohort of interest: females aged 52-62 with post-cardiac arrest
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'Cardiac Arrest'
),

-- ICU stays for cohort
cohort_icu AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    cohort c ON i.hadm_id = c.hadm_id
),

-- Critical lab events in first 48h
lab_events AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    ce.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    cohort_icu ci ON ce.stay_id = ci.stay_id
  WHERE 
    ce.charttime BETWEEN ci.intime AND TIMESTAMP_ADD(ci.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN ( -- example critical lab events, adjust as needed
      220050,  -- Heart Rate
      220179,  -- Respiratory Rate
      220052   -- Blood Pressure
    )
)

-- Final query
SELECT 
  APPROX_QUANTILES(l.valuenum, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(l.valuenum, 4)[OFFSET(2)] AS median,
  AVG(ci.los) AS avg_los,
  SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(c.hadm_id) AS mortality_rate
FROM 
  cohort c
JOIN 
  cohort_icu ci ON c.hadm_id = ci.hadm_id
JOIN 
  lab_events l ON ci.stay_id = l.stay_id;