WITH 
-- Target population: Female inpatients aged 53-63 with pulmonary embolism
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code LIKE '415.1%'  -- Pulmonary embolism ICD-9 code
        OR icd_code LIKE 'I26.%'  -- Pulmonary embolism ICD-10 code
    )
),

-- Calculate lab instability score for the first 72 hours
lab_instability_score AS (
  SELECT 
    tp.hadm_id,
    COUNT(CASE 
            WHEN 
              (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) 
              OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper) 
            THEN 1 
          END) AS lab_instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    target_population tp 
      ON le.hadm_id = tp.hadm_id
  WHERE 
    le.charttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 72 HOUR)
  GROUP BY 
    tp.hadm_id
),

-- Determine 75th percentile threshold
percentile_threshold AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 0.75)[OFFSET(1)] AS percentile_75
  FROM 
    lab_instability_score
)

-- Analyze patients ≥ 75th percentile threshold
SELECT 
  COUNT(DISTINCT lis.hadm_id) AS num_patients,
  SUM(CASE 
          WHEN tp.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END) / COUNT(DISTINCT lis.hadm_id) * 100 AS mortality_rate,
  AVG(TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY)) AS mean_los_days
FROM 
  target_population tp
JOIN 
  lab_instability_score lis 
    ON tp.hadm_id = lis.hadm_id
JOIN 
  percentile_threshold pt 
    ON lis.lab_instability_score >= pt.percentile_75;