WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND adm.admission_location = 'EMERGENCY ROOM'
)

SELECT
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'died' 
    ELSE 'alive' 
  END AS discharge_status,
  COUNT(*) AS total_patients,
  -- Proportions
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_los_ge7,
  SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(*)) AS proportion_los_ge14,
  -- Percentile rank for 10-day LOS (as proportion ≤10 days, scaled to percentage)
  SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(*)) * 100 AS percentile_rank_10_day
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY discharge_status;