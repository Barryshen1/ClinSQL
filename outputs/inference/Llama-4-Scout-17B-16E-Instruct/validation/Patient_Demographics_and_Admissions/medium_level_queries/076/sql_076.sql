WITH 
  patient_stays AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      CASE 
        WHEN a.dischtime IS NOT NULL THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
        ELSE TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      END AS los,
      a.hospital_expire_flag,
      CASE 
        WHEN a.hospital_expire_flag = 0 THEN 'Alive'
        WHEN a.hospital_expire_flag = 1 THEN 'Dead'
      END AS status
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
  ),
  stats AS (
    SELECT 
      status,
      APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median,
      APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75,
      APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90,
      AVG(los) AS mean
    FROM 
      patient_stays
    GROUP BY 
      status
  ),
  percentile_rank AS (
    SELECT 
      COUNTIF(los <= 5) / COUNT(los) AS percentile_rank_5days
    FROM 
      patient_stays
  )

SELECT 
  status,
  median,
  p75,
  p90,
  mean
FROM 
  stats
UNION ALL
SELECT 
  'Percentile Rank of 5 days' AS status,
  percentile_rank_5days,
  NULL,
  NULL,
  NULL
FROM 
  percentile_rank;