WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
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
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 44 AND 54
    AND d.icd_code LIKE '%410%'  -- AMI ICD code approximation
),

-- Get lab results
lab_results AS (
  SELECT 
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM cohort)
),

-- Calculate lab instability score
lab_instability AS (
  SELECT 
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom,
    LAG(valuenum) OVER (PARTITION BY hadm_id, itemid ORDER BY charttime) AS prev_valuenum
  FROM 
    lab_results
),

-- Calculate lab instability score
score AS (
  SELECT 
    hadm_id,
    charttime,
    itemid,
    ABS(valuenum - prev_valuenum) / prev_valuenum AS instability_score
  FROM 
    lab_instability
  WHERE 
    prev_valuenum IS NOT NULL
    AND prev_valuenum != 0
)

-- Final query
SELECT 
  APPROX_QUANTILES(instability_score, 1000)[75] AS percentile_75_instability_score
FROM 
  score
  WHERE charttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR);