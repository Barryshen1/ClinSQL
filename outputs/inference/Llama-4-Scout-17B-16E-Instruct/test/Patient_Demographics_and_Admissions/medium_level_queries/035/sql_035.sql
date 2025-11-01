WITH 
  patient_data AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.admission_location,
      p.anchor_age,
      p.gender,
      a.hospital_expire_flag,
      a.discharge_location
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 43 AND 53
      AND a.admission_location = 'ED'
  ),
  
  los_data AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'Death'
        WHEN discharge_location LIKE '%Facility%' THEN 'Facility'
        ELSE 'Home' 
      END AS discharge_outcome
    FROM 
      patient_data
  ),
  
  ranked_los AS (
    SELECT 
      discharge_outcome,
      los,
      PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los) AS percentile_rank
    FROM 
      los_data
  )

SELECT 
  discharge_outcome,
  APPROX_QUANTILES(los, 1000)[500] AS median_los,
  APPROX_QUANTILES(los, 1000)[250] AS q1,
  APPROX_QUANTILES(los, 1000)[750] AS q3,
  AVG(CASE WHEN los = 14 THEN percentile_rank ELSE NULL END) AS percentile_rank_14d
FROM 
  ranked_los
GROUP BY 
  discharge_outcome;