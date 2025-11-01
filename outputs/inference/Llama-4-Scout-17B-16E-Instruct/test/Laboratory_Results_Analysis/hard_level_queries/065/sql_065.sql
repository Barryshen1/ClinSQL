WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    d.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND d.icd_code LIKE '%K92.2%'  -- Lower GI bleeding
    AND a.admittime >= TIMESTAMP_SUB(CURRENT_TIMESTAMP, INTERVAL 3 DAY)
),

-- Lab events for cohort
lab_events_cohort AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT CASE WHEN valuenum IS NOT NULL AND valueuom IS NOT NULL THEN labevent_id END) AS lab_events
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

-- General inpatient lab events
lab_events_general AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT CASE WHEN valuenum IS NOT NULL AND valueuom IS NOT NULL THEN labevent_id END) AS lab_events
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

-- Cohort LOS and mortality
cohort_outcomes AS (
  SELECT 
    c.hadm_id,
    a.dischtime - a.admittime AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS mortality
  FROM 
    cohort c
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON c.hadm_id = a.hadm_id
)

-- Final query
SELECT 
  APPROX_QUANTILES(le.lab_events, 4)[OFFSET(1)] AS lab_instability_score_25th_percentile,
  AVG(le.lab_events) AS avg_lab_events_cohort,
  AVG(general.lab_events) AS avg_lab_events_general,
  AVG(co_outcomes.los) AS avg_los,
  AVG(co_outcomes.mortality) AS mortality_rate
FROM 
  lab_events_cohort le
  JOIN cohort c ON le.hadm_id = c.hadm_id
  JOIN lab_events_general general ON c.hadm_id = general.hadm_id
  JOIN cohort_outcomes co_outcomes ON c.hadm_id = co_outcomes.hadm_id;