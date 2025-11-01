WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.discharge_location,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 81 AND 91
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.hadm_id = a.hadm_id AND t.careunit LIKE 'HOSP%'
      )
  ),

  -- Calculate hospital LOS and discharge category
  hospital_los AS (
    SELECT 
      hadm_id,
      dischtime,
      hospital_expire_flag,
      discharge_location,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
    FROM 
      patients_of_interest
  ),

  -- Categorize discharge
  discharge_category AS (
    SELECT 
      hadm_id,
      los,
      CASE
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN discharge_location LIKE '%HOME%' THEN 'Home'
        WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
        ELSE 'Other'
      END AS discharge_location
    FROM 
      hospital_los
  )

SELECT 
  discharge_location,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 0.25)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los, 0.5)[OFFSET(1)] AS p50_los,
  APPROX_QUANTILES(los, 0.75)[OFFSET(1)] AS p75_los,
  APPROX_QUANTILES(los, 0.9)[OFFSET(1)] AS p90_los,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_los_leq_10_days
FROM 
  discharge_category
WHERE 
  discharge_location IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY 
  discharge_location;