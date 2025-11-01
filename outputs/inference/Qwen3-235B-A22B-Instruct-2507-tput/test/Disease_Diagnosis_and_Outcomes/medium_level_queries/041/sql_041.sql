WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND (
      SUBSTR(icd_code, 1, 3) = 'A40' OR 
      SUBSTR(icd_code, 1, 3) = 'A41' OR 
      icd_code = 'R6520'
    ))
  )
),
septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 10 AND icd_code = 'R6521')
),
patients_with_sepsis AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN sepsis_codes s
    ON diag.icd_code = s.icd_code
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
    INNER JOIN septic_shock_codes ss
      ON diag2.icd_code = ss.icd_code
    WHERE diag2.hadm_id = adm.hadm_id
  )
),
cohort AS (
  SELECT
    adm.hadm_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN adm.deathtime IS NOT NULL THEN DATETIME_DIFF(adm.deathtime, adm.admittime, HOUR) / 24.0
      ELSE NULL
    END AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN patients_with_sepsis ps
    ON adm.hadm_id = ps.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
stratified AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    time_to_death_days,
    CASE
      WHEN los_days <= 7 THEN 'LOS <=7 days'
      ELSE 'LOS >7 days'
    END AS los_group
  FROM cohort
  WHERE los_days IS NOT NULL
),
mortality_summary AS (
  SELECT
    los_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 1, time_to_death_days, NULL), 100)[OFFSET(50)] AS median_time_to_death_days
  FROM stratified
  GROUP BY los_group
)
SELECT
  los_group,
  n,
  deaths,
  ROUND(100 * mortality_rate, 2) AS mortality_rate_percent,
  median_time_to_death_days
FROM mortality_summary
ORDER BY los_group;