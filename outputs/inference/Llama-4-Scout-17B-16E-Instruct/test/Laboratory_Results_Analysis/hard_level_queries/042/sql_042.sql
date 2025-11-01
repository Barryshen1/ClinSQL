WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 73 AND 83 
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN ('431', 'I61')
    )
),

-- Identify abnormal lab events within 48 hours
abnormal_labs AS (
  SELECT 
    a.hadm_id, 
    le.itemid, 
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    patients_of_interest a 
      ON le.hadm_id = a.hadm_id
  WHERE 
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  AND 
    le.valuenum IS NOT NULL 
  AND 
    (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
  AND 
    (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
),

-- Calculate 48-hour instability score
instability_score AS (
  SELECT 
    hadm_id, 
    COUNT(DISTINCT itemid) as score
  FROM 
    abnormal_labs
  GROUP BY 
    hadm_id
),

-- Merge with patient data and calculate outcomes
outcomes AS (
  SELECT 
    io.hadm_id, 
    io.score,
    a.dischtime, 
    a.deathtime,
    a.admittime
  FROM 
    instability_score io
  JOIN 
    patients_of_interest a 
      ON io.hadm_id = a.hadm_id
),

-- Calculate quartiles of instability score
quartiles AS (
  SELECT 
    hadm_id,
    score,
    NTILE(4) OVER (ORDER BY score) as quartile
  FROM 
    instability_score
)

-- Final aggregation
SELECT 
  q.quartile,
  COUNT(DISTINCT o.hadm_id) as count,
  AVG(TIMESTAMP_DIFF(o.dischtime, o.admittime, DAY)) as mean_los,
  SUM(CASE WHEN o.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT o.hadm_id) as mortality
FROM 
  outcomes o
JOIN 
  quartiles q ON o.hadm_id = q.hadm_id
GROUP BY 
  q.quartile
ORDER BY 
  q.quartile;