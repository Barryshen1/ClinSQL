WITH first_service AS (
  SELECT 
    hadm_id, 
    curr_service
  FROM (
    SELECT 
      hadm_id, 
      curr_service, 
      transfertime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.services`
  )
  WHERE rn = 1
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'dead' 
      ELSE 'alive' 
    END AS status_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN first_service fs
    ON adm.hadm_id = fs.hadm_id
  WHERE
    adm.admission_type IN ('URGENT', 'EMERGENCY')
    AND fs.curr_service = 'MEDICINE'
    AND pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 57 AND 67
    AND adm.dischtime IS NOT NULL  -- Ensure admission has ended
)
SELECT
  status_group,
  COUNT(*) AS num_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[SAFE_ORDINAL(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[SAFE_ORDINAL(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[SAFE_ORDINAL(90)] AS p90_los,
  ROUND(SAFE_DIVIDE(COUNTIF(los_days <= 5), COUNT(*)) * 100, 2) AS percentile_rank_5day
FROM cohort
GROUP BY status_group;