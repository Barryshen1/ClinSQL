WITH 
  patient_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.discharge_location,
      CASE 
        WHEN a.deathtime IS NOT NULL THEN 'In-hospital death'
        WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_outcome,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 86 AND 96
  ),
  los_stats AS (
    SELECT 
      discharge_outcome,
      APPROX_QUANTILES(los, 1000)[OFFSET(1)] AS mean_los,
      APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
      APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
      APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
      APPROX_QUANTILES(los, 1000)[OFFSET(100)] AS p10_los
    FROM 
      patient_admissions
    GROUP BY 
      discharge_outcome
  )

SELECT 
  discharge_outcome,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  p10_los AS percentile_10d
FROM 
  los_stats
ORDER BY 
  discharge_outcome;