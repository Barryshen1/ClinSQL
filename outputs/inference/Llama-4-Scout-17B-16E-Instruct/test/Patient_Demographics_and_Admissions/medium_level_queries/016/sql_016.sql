WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.discharge_location,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 44 AND 54
      AND a.discharge_location IN ('Home', 'Hospice', 'Death')
  ),

  -- Calculate percentiles of LOS
  los_percentiles AS (
    SELECT 
      discharge_location,
      APPROX_QUANTILES(los, 0.5)[OFFSET(0)] AS p50,
      APPROX_QUANTILES(los, 0.75)[OFFSET(0)] AS p75,
      APPROX_QUANTILES(los, 0.9)[OFFSET(0)] AS p90,
      APPROX_QUANTILES(los, 0.95)[OFFSET(0)] AS p95
    FROM 
      patients_of_interest
    GROUP BY 
      discharge_location
  ),

  -- Calculate percentile rank of a 7-day stay
  percentile_rank AS (
    SELECT 
      discharge_location,
      los,
      PERCENT_RANK() OVER (PARTITION BY discharge_location ORDER BY los) AS percentile_rank
    FROM 
      patients_of_interest
  ),

  percentile_rank_7_days AS (
    SELECT 
      discharge_location,
      percentile_rank
    FROM 
      percentile_rank
    WHERE 
      los = 7
  )

-- Combine results
SELECT 
  lp.discharge_location,
  lp.p50,
  lp.p75,
  lp.p90,
  lp.p95,
  COALESCE(prd.percentile_rank, 0) AS percentile_rank_7_days
FROM 
  los_percentiles lp
  LEFT JOIN percentile_rank_7_days prd 
  ON lp.discharge_location = prd.discharge_location;