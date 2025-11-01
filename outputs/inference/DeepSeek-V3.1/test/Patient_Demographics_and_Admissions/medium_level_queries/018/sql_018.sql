WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'Death'
      WHEN adm.discharge_location LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND (adm.admission_type = 'TRANSFER' OR adm.admission_location = 'TRANSFER FROM HOSPITAL')
    AND adm.dischtime IS NOT NULL
),

stats AS (
  SELECT
    discharge_category,
    COUNT(*) AS n_patients,
    PERCENTILE_DISC(los_days, 0.5) OVER (PARTITION BY discharge_category) AS median_los,
    PERCENTILE_DISC(los_days, 0.25) OVER (PARTITION BY discharge_category) AS q1_los,
    PERCENTILE_DISC(los_days, 0.75) OVER (PARTITION BY discharge_category) AS q3_los,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS los_leq_10
  FROM cohort
  GROUP BY discharge_category, los_days  -- Note: PERCENTILE_DISC requires grouping by the value column? Actually, we need to use a different approach.
)

-- Alternatively, we can use approximate percentiles with one pass.
-- Let's use APPROX_QUANTILES for median and IQR in a grouped way.
, quantiles AS (
  SELECT
    discharge_category,
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100) [OFFSET(25)] AS q1_los,
    APPROX_QUANTILES(los_days, 100) [OFFSET(75)] AS q3_los,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS los_leq_10
  FROM cohort
  GROUP BY discharge_category
)

SELECT
  discharge_category,
  n_patients,
  median_los,
  q1_los,
  q3_los,
  ROUND(los_leq_10 * 100.0 / n_patients, 2) AS percent_los_leq_10
FROM quantiles
ORDER BY discharge_category;