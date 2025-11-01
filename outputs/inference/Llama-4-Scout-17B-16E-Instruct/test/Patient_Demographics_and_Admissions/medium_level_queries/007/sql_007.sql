WITH 
  -- Identify relevant admissions
  eligible_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      CASE 
        WHEN t.transfer_id IS NOT NULL THEN 1 
        ELSE 0 
      END AS transferred
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.transfers` t 
        ON a.hadm_id = t.hadm_id AND t.eventtype = 'transfer in'
    WHERE 
      p.anchor_age BETWEEN 78 AND 88
      AND p.gender = 'M'
      AND a.admission_location != 'home'
  ),
  
  -- Calculate LOS and survival status
  admission_outcomes AS (
    SELECT 
      hadm_id,
      subject_id,
      TIMESTAMP_DIFF(COALESCE(dischtime, deathtime), admittime, DAY) AS los,
      hospital_expire_flag
    FROM 
      eligible_admissions
  )

-- Calculate percentiles and counts
SELECT 
  'Survived' AS outcome,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los
FROM 
  admission_outcomes
WHERE 
  hospital_expire_flag = 0
UNION ALL
SELECT 
  'In-hospital death' AS outcome,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los
FROM 
  admission_outcomes
WHERE 
  hospital_expire_flag = 1
;

-- Percentile rank of a 10-day LOS
SELECT 
  APPROX_PERCENTILE(10, los) AS percentile_rank
FROM 
  admission_outcomes;