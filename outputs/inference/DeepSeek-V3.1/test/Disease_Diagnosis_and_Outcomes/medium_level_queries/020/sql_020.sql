WITH sepsis_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    -- Calculate LOS in days (using dischtime or deathtime if died in hospital)
    DATETIME_DIFF(
      COALESCE(adm.dischtime, adm.deathtime), 
      adm.admittime, 
      DAY
    ) AS los_days,
    -- Group LOS
    CASE 
      WHEN DATETIME_DIFF(
          COALESCE(adm.dischtime, adm.deathtime), 
          adm.admittime, 
          DAY
        ) <= 3 THEN '<=3'
      WHEN DATETIME_DIFF(
          COALESCE(adm.dischtime, adm.deathtime), 
          adm.admittime, 
          DAY
        ) BETWEEN 4 AND 6 THEN '4-6'
      WHEN DATETIME_DIFF(
          COALESCE(adm.dischtime, adm.deathtime), 
          adm.admittime, 
          DAY
        ) BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_group,
    -- Check if ICU on day 1 (within 24h of admission and after admission)
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = adm.hadm_id 
        AND icu.intime >= adm.admittime
        AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
      ) THEN 'ICU on day1'
      ELSE 'No ICU on day1'
    END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 86 AND 96
    AND pat.gender = 'M'
    -- Filter for sepsis (ICD-10 codes) but exclude septic shock
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        (diag.icd_code LIKE 'A41%'    -- Sepsis
        OR diag.icd_code = 'T81.12'   -- Postprocedural sepsis
        OR diag.icd_code = 'R65.20')  -- Severe sepsis without shock
        AND diag.icd_version = 10
    )
    -- Exclude septic shock
    AND adm.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        (diag.icd_code = 'R65.21'   -- Severe sepsis with septic shock
        OR diag.icd_code = 'R57.2') -- Septic shock
        AND diag.icd_version = 10
    )
)

SELECT 
  los_group,
  icu_day1,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS died_in_hospital,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  -- Median days to death (only for those who died) - using approx_quantiles
  (APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, DAY) ELSE NULL END,
    2
  ))[OFFSET(1)] AS median_days_to_death
FROM sepsis_cohort
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;