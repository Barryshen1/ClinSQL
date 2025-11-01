WITH 
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' AND
    p.anchor_age BETWEEN 89 AND 99
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE hadm_id = a.hadm_id AND icd_code LIKE '% septic shock%'
    )
),

cohort_icu AS (
  SELECT 
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    cohort c
  ON 
    i.hadm_id = c.hadm_id
  WHERE 
    i.intime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
),

instability_scores AS (
  SELECT 
    stay_id,
    hadm_id,
    charttime,
    CAST(value AS FLOAT64) AS value,
    itemid
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid = 220050  
    AND stay_id IN (SELECT stay_id FROM cohort_icu)
),

stats AS (
  SELECT 
    APPROX_QUANTILES(value, 4) AS quantiles
  FROM 
    instability_scores
  WHERE 
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 2 DAY)
),

abnormal_labs AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    valuenum > 100
    AND subject_id IN (SELECT subject_id FROM cohort)
  GROUP BY 
    subject_id, hadm_id
),

cohort_los AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(outtime, intime, DAY) AS los
  FROM 
    cohort_icu
),

cohort_mortality AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    cohort c
  ON 
    a.hadm_id = c.hadm_id
)

SELECT 
  quantiles[OFFSET(1)] AS Q1,
  quantiles[OFFSET(2)] AS median,
  quantiles[OFFSET(3)] AS Q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS IQR,
  AVG(abnormal_lab_count) AS avg_abnormal_labs,
  AVG(los) AS avg_los,
  AVG(mortality) AS mortality_rate
FROM 
  stats
  CROSS JOIN (
    SELECT 
      AVG(abnormal_lab_count) AS abnormal_lab_count,
      AVG(los) AS los,
      AVG(mortality) AS mortality
    FROM 
      abnormal_labs
      CROSS JOIN cohort_los
      CROSS JOIN cohort_mortality
  );