WITH 
  -- Filter and calculate LOS
  admissions_filtered AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_type,
      p.anchor_age,
      p.gender,
      CASE
        WHEN a.deathtime IS NOT NULL THEN 'In-hospital death'
        WHEN a.discharge_location LIKE '%Hospice%' THEN 'Hospice'
        ELSE 'Discharged home'
      END AS disposition
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
      AND a.admission_type = 'Emergency'
  )

-- Calculate LOS and statistics
SELECT 
  disposition,
  APPROX_QUANTILES(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY), 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY), 1000)[OFFSET(250)] AS q1_los,
  APPROX_QUANTILES(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY), 1000)[OFFSET(750)] AS q3_los
FROM 
  admissions_filtered
GROUP BY 
  disposition;