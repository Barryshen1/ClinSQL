WITH cohort AS (
  -- Base cohort: females 40-50
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

neutropenia AS (
  -- Admissions with neutropenia (neutrophils < 500) in first 48h
  SELECT DISTINCT
    c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
      ON le.itemid = dli.itemid
    WHERE le.hadm_id = c.hadm_id
      AND le.charttime >= c.admittime
      AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND dli.label LIKE '%Neutrophils%'
      AND dli.category = 'Blood Counts'
      AND le.valuenum < 500
      AND le.valuenum IS NOT NULL
  )
),

fever AS (
  -- Admissions with fever (>=38.3C) in first 48h
  SELECT DISTINCT
    c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE ce.hadm_id = c.hadm_id
      AND ce.charttime >= c.admittime
      AND ce.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND di.label = 'Temperature Celsius'
      AND SAFE_CAST(ce.valuenum AS FLOAT64) >= 38.3
      AND ce.valuenum IS NOT NULL
  )
),

qualifying_admissions AS (
  -- Cohort with neutropenic fever
  SELECT 
    c.*
  FROM cohort c
  INNER JOIN neutropenia n ON c.hadm_id = n.hadm_id
  INNER JOIN fever f ON c.hadm_id = f.hadm_id
),

med_score AS (
  -- Medication complexity score: unique meds in first 48h
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    qa.admittime,
    qa.dischtime,
    qa.hospital_expire_flag,
    COALESCE(
      (SELECT COUNT(DISTINCT ie.itemid)
       FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
       INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
       WHERE ie.hadm_id = qa.hadm_id
         AND di.category = 'Medications'
         AND ie.starttime >= qa.admittime
         AND ie.starttime <= TIMESTAMP_ADD(qa.admittime, INTERVAL 48 HOUR)
         AND ie.statusdescription != 'Rewritten'), 0
    ) + 
    (SELECT COUNT(DISTINCT SAFE_CAST(ps.drug AS STRING))
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` ps
     WHERE ps.hadm_id = qa.hadm_id
       AND ps.starttime >= qa.admittime
       AND ps.starttime <= TIMESTAMP_ADD(qa.admittime, INTERVAL 48 HOUR)
       AND ps.drug IS NOT NULL
    ) AS score
  FROM qualifying_admissions qa
),

outcomes AS (
  -- Add LOS
  SELECT 
    ms.*,
    TIMESTAMP_DIFF(ms.dischtime, ms.admittime, DAY) AS los_days
  FROM med_score ms
),

readmissions AS (
  -- 30-day readmission: flag if next admission within 30d of discharge (per patient)
  SELECT 
    o.subject_id,
    o.hadm_id,
    CASE 
      WHEN next_dischtime IS NOT NULL 
        AND next_admittime <= TIMESTAMP_ADD(o.dischtime, INTERVAL 30 DAY)
      THEN 1.0 ELSE 0.0 
    END AS readmit_30d_flag
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      LAG(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_admittime,
      LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
    FROM outcomes
  ) o
  LEFT JOIN (
    SELECT 
      subject_id,
      admittime,
      dischtime
    FROM outcomes
  ) next ON o.subject_id = next.subject_id 
    AND next.admittime > o.admittime
    AND next.admittime = FIRST_VALUE(next.admittime) OVER (
      PARTITION BY o.subject_id 
      ORDER BY next.admittime 
      ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
    )
  WHERE o.prev_admittime IS NULL  -- Only index admissions (first per patient, but actually per admission; adjust if needed)
),

final_data AS (
  -- Combine outcomes and readmits
  SELECT 
    o.*,
    COALESCE(r.readmit_30d_flag, 0) AS readmit_30d_flag,
    NTILE(4) OVER (ORDER BY o.score) AS quartile
  FROM outcomes o
  LEFT JOIN readmissions r ON o.hadm_id = r.hadm_id
)

-- Stratified results
SELECT 
  quartile,
  COUNT(*) AS admission_count,
  AVG(score) AS mean_score,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) * 100, 2) AS mortality_pct,
  ROUND(SAFE_DIVIDE(SUM(readmit_30d_flag), COUNT(DISTINCT subject_id)) * 100, 2) AS readmission_30d_pct
FROM final_data
GROUP BY quartile
ORDER BY quartile;