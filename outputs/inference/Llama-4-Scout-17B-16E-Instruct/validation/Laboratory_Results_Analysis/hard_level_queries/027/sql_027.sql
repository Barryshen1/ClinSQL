WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    p.dod,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 89 AND 99
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'K62.1'  -- Lower GI bleeding
    )
),

-- Retrieve lab events for patients of interest within 72 hours of admission
lab_events_72hrs AS (
  SELECT 
    hadm_id,
    subject_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_of_interest)
    AND charttime BETWEEN (SELECT admittime FROM patients_of_interest p WHERE p.hadm_id = hadm_id) 
                         AND TIMESTAMP_ADD((SELECT admittime FROM patients_of_interest p WHERE p.hadm_id = hadm_id), INTERVAL 72 HOUR)
),

-- Simplified lab instability score calculation (example: based on creatinine levels)
lab_instability_score AS (
  SELECT 
    hadm_id,
    subject_id,
    -- Example calculation: average creatinine level over 72 hours
    AVG(CASE WHEN itemid = 220050  THEN valuenum END) AS creatinine_avg
  FROM 
    lab_events_72hrs
  GROUP BY 
    hadm_id, subject_id
),

-- Stratify patients into quintiles based on lab instability score
quintiles AS (
  SELECT 
    hadm_id,
    subject_id,
    creatinine_avg,
    NTILE(5) OVER (ORDER BY creatinine_avg) AS quintile
  FROM 
    lab_instability_score
)

-- Final calculation: LOS, mortality, and comparison
SELECT 
  q.quintile,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM 
  patients_of_interest a
JOIN 
  quintiles q ON a.hadm_id = q.hadm_id
GROUP BY 
  q.quintile
ORDER BY 
  q.quintile;