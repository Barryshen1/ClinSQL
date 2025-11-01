WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('99591', '99592'))) OR
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520'))
),
shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '78552') OR
    (icd_version = 10 AND icd_code = 'R6521')
),
base AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
      WHERE icu.hadm_id = adm.hadm_id 
        AND icu.intime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 86 AND 96
    AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM shock_admissions)
)
SELECT
  CASE
    WHEN los_days <= 3 THEN '<=3'
    WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
    WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_group,
  icu_day1,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage,
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 1 THEN los_days ELSE NULL END, 
    2
  )[OFFSET(1)] AS median_days_to_death
FROM base
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;