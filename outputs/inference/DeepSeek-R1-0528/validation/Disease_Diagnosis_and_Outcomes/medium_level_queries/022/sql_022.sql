WITH sepsis_without_shock AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- Sepsis codes
    (icd_version = 9 AND icd_code LIKE '038%') OR
    (icd_version = 10 AND icd_code LIKE 'A41%')
    AND hadm_id NOT IN (
      -- Exclude septic shock
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code = '78552') OR
        (icd_version = 10 AND icd_code = 'R6521')
    )
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    patients.gender,
    patients.anchor_age,
    patients.anchor_year,
    -- Calculate age at admission
    patients.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - patients.anchor_year) AS age_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON adm.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'M'
    AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_without_shock)
),
cohort_with_icu_los AS (
  SELECT
    c.*,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
    -- Check ICU admission within 24 hours of hospital admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE 
          icu.hadm_id = c.hadm_id
          AND icu.intime >= c.admittime
          AND icu.intime < DATETIME_ADD(c.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes'
      ELSE 'No'
    END AS icu_day1
  FROM cohort c
  WHERE 
    age_admission BETWEEN 50 AND 60  -- Age filter
)
SELECT
  CASE 
    WHEN los <= 7 THEN 'LOS ≤7'
    ELSE 'LOS >7'
  END AS los_group,
  icu_day1,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM cohort_with_icu_los
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;