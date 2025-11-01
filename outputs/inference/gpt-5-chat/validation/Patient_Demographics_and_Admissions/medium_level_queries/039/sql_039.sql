WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    -- compute LOS in days as a float
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(adm.discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
    AND UPPER(adm.admission_type) IN ('URGENT','EMERGENCY')
)
SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 4)[OFFSET(1)], 2) AS p25_los_days,
  ROUND(APPROX_QUANTILES(los_days, 4)[OFFSET(2)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 4)[OFFSET(3)], 2) AS p75_los_days,
  -- percentile rank of a 7-day LOS: proportion <= 7 days
  ROUND(100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_rank_of_7day
FROM cohort
GROUP BY discharge_category
ORDER BY discharge_category;