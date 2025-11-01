WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'DEATH'
      WHEN adm.discharge_location LIKE '%HOSPICE%' THEN 'HOSPICE'
      WHEN adm.discharge_location = 'HOME' THEN 'HOME'
    END AS outcome_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    adm.admission_type = 'EMERGENCY'
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 57 AND 67
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
),
aggregated AS (
  SELECT 
    outcome_group,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
    NULL AS percentile_rank_10d
  FROM cohort
  WHERE outcome_group IS NOT NULL
  GROUP BY outcome_group
),
percentile_rank AS (
  SELECT 
    'Entire Cohort' AS outcome_group,
    NULL AS n,
    NULL AS mean_los,
    NULL AS median_los,
    NULL AS p75_los,
    NULL AS p90_los,
    COUNTIF(los <= 10) / COUNT(*) AS percentile_rank_10d
  FROM cohort
)
SELECT * FROM aggregated
UNION ALL
SELECT * FROM percentile_rank
ORDER BY outcome_group;