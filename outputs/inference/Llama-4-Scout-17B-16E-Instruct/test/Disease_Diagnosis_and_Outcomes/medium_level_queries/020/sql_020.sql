WITH 
  -- Define the population of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.deathtime,
      a.hospital_expire_flag,
      icu.intime AS icu_admittime,
      DATE_DIFF(a.dischtime, a.admittime, 'DAY') AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON 
      a.hadm_id = icu.hadm_id
    WHERE 
      a.admission_type NOT IN ('elective')
      AND a.gender = 'M'
      AND a.anchor_age BETWEEN 86 AND 96
  ),

  -- Identify patients with sepsis (excluding septic shock)
  sepsis_patients AS (
    SELECT 
      subject_id,
      hadm_id,
      hospital_expire_flag,
      los,
      icu_admittime,
      deathtime
    FROM 
      patients_of_interest
    WHERE 
      hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '995.90' OR icd_code LIKE ' sepsis'
      )
      AND hadm_id NOT IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '995.92' OR icd_code LIKE 'septic shock'
      )
  ),

  -- Calculate days to death for those who died
  deaths AS (
    SELECT 
      subject_id,
      hadm_id,
      DATE_DIFF(deathtime, icu_admittime, 'DAY') AS days_to_death
    FROM 
      sepsis_patients
    WHERE 
      hospital_expire_flag = 1
  )

SELECT 
  CASE 
    WHEN los <= 3 THEN '≤3'
    WHEN los BETWEEN 4 AND 6 THEN '4–6'
    WHEN los BETWEEN 7 AND 10 THEN '7–10'
    ELSE '>10'
  END AS los_group,
  hospital_expire_flag,
  COUNT(*) AS count,
  APPROX_QUANTILES(days_to_death, 0.5)[OFFSET(1)] AS median_days_to_death
FROM 
  sepsis_patients
  LEFT JOIN deaths ON sepsis_patients.hadm_id = deaths.hadm_id
GROUP BY 
  los_group,
  hospital_expire_flag
ORDER BY 
  los_group,
  hospital_expire_flag;