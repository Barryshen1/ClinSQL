WITH hf_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
    END AS los_group,
    -- Time to death in days (for those who died)
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN DATE_DIFF(adm.deathtime, adm.admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'  -- ICD-10 codes for heart failure
        AND icd_version = 10
    )
)

SELECT 
  los_group,
  COUNT(*) AS n_admissions,
  -- Mortality count
  SUM(hospital_expire_flag) AS n_died,
  -- Mortality percentage
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  -- 95% CI for mortality percentage (normal approximation)
  ROUND(100 * (SUM(hospital_expire_flag) / COUNT(*) - 1.96 * SQRT( (SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*) )), 2) AS ci_lower,
  ROUND(100 * (SUM(hospital_expire_flag) / COUNT(*) + 1.96 * SQRT( (SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*) )), 2) AS ci_upper,
  -- Median time to death (only for those who died) using APPROX_QUANTILES
  ROUND(APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)], 2) AS median_time_to_death_days
FROM hf_admissions
WHERE los_group IS NOT NULL  -- Exclude LOS=0 or negative
GROUP BY los_group
ORDER BY los_group;