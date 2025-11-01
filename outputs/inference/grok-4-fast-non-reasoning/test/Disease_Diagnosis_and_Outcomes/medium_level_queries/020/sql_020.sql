WITH cohort AS (
  -- Base cohort: male patients aged 86-96 with sepsis (ICD-10/9, excluding septic shock)
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- LOS bin (matched to question: ≤3/4–6/7–10/>10)
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '≤3'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 6 THEN '4-6'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) <= 10 THEN '7-10'
      ELSE '>10'
    END AS los_bin
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND EXISTS (
      -- Sepsis diagnosis (ICD-10/9 codes, exclude septic shock)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          -- ICD-10: Sepsis/severe sepsis (exclude shock)
          (d.icd_version = '10' AND (
            d.icd_code LIKE 'A40.%' OR d.icd_code LIKE 'A41.%' OR 
            d.icd_code = 'R65.20' OR d.icd_code = 'R65.2' OR
            d.icd_code LIKE 'P36.%'
          ) AND d.icd_code NOT LIKE 'R65.2[1|9]%')
          OR
          -- ICD-9: Sepsis (exclude shock equivalents)
          (d.icd_version = '9' AND (
            d.icd_code = '995.91' OR d.icd_code = '995.92' OR
            d.icd_code LIKE '038.%' OR d.icd_code LIKE '785.5[2|9]'
          ))
        )
    )
),
icu_status AS (
  -- Determine day-1 ICU status using icustays
  SELECT 
    c.*,
    -- First ICU stay intime (if any)
    MIN(i.intime) AS first_icu_intime
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.deathtime, 
    c.hospital_expire_flag, c.gender, c.anchor_age, c.los_days, c.los_bin
),
day1_icu AS (
  SELECT 
    *,
    -- Day-1 ICU status
    CASE 
      WHEN first_icu_intime IS NULL THEN 'No ICU'
      WHEN DATE(admittime) = DATE(first_icu_intime) THEN 'ICU (day 1)'
      ELSE 'ICU (not day 1)'
    END AS day1_icu_status,
    -- Days to death (deceased only)
    CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY) END AS days_to_death
  FROM icu_status
)
-- Mortality table by LOS bin and day-1 ICU status
SELECT 
  los_bin,
  day1_icu_status,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct
FROM day1_icu
GROUP BY los_bin, day1_icu_status
ORDER BY 
  CASE los_bin 
    WHEN '≤3' THEN 1 
    WHEN '4-6' THEN 2 
    WHEN '7-10' THEN 3 
    ELSE 4 
  END,
  CASE day1_icu_status 
    WHEN 'No ICU' THEN 1 
    WHEN 'ICU (day 1)' THEN 2 
    ELSE 3 
  END

UNION ALL

-- Overall median days-to-death (deceased only; padded to match columns)
SELECT 
  NULL AS los_bin,
  NULL AS day1_icu_status,
  NULL AS total_admissions,
  NULL AS deaths,
  PERCENTILE_CONT(days_to_death, 0.5) AS median_days_to_death
FROM day1_icu
WHERE hospital_expire_flag = 1 AND days_to_death IS NOT NULL;