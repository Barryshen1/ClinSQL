WITH 
sepsis_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Sepsis%' OR d_icd.long_title LIKE '%septic shock%'
),

patient_info AS (
  SELECT 
    pat.subject_id,
    pat.gender,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    icu.intime,
    icu.outtime,
    CASE WHEN adm.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality,
    TIMESTAMP_DIFF(adm.deathtime, adm.admittime, HOUR) AS time_to_death_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON pat.subject_id = adm.subject_id
  JOIN sepsis_patients ON adm.hadm_id = sepsis_patients.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'F' AND pat.anchor_age BETWEEN 53 AND 63
),

patient_los AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(outtime, intime, DAY) AS los,
    CASE WHEN TIMESTAMP_DIFF(outtime, intime, DAY) <= 7 THEN 'LOS <= 7'
         ELSE 'LOS > 7' END AS los_category,
    in_hospital_mortality,
    time_to_death_hours
  FROM patient_info
),

mortality_rates AS (
  SELECT 
    los_category,
    COUNT(*) AS N,
    AVG(in_hospital_mortality) * 100 AS mortality_rate,
    APPROX_QUANTILES(time_to_death_hours, 100)[OFFSET(50)] AS median_time_to_death_hours
  FROM patient_los
  GROUP BY los_category
)

SELECT 
  los_category,
  N,
  mortality_rate AS in_hospital_mortality_percent,
  median_time_to_death_hours
FROM mortality_rates
UNION ALL
SELECT 
  'Absolute Mortality Difference',
  NULL,
  (SELECT mortality_rate FROM mortality_rates WHERE los_category = 'LOS > 7') - 
  (SELECT mortality_rate FROM mortality_rates WHERE los_category = 'LOS <= 7'),
  NULL
UNION ALL
SELECT 
  'Relative Mortality Difference (%)',
  NULL,
  ((SELECT mortality_rate FROM mortality_rates WHERE los_category = 'LOS > 7') / 
   (SELECT mortality_rate FROM mortality_rates WHERE los_category = 'LOS <= 7') - 1) * 100,
  NULL;