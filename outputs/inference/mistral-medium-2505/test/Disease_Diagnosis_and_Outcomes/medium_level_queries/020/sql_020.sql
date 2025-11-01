WITH sepsis_patients AS (
  -- Get male patients aged 86-96 with sepsis (excluding septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3 THEN '≤3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10 days'
      ELSE '>10 days'
    END AS los_category,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = a.subject_id
        AND i.hadm_id = a.hadm_id
        AND TIMESTAMP_DIFF(i.intime, a.admittime, HOUR) <= 24
      ) THEN 'Yes'
      ELSE 'No'
    END AS day1_icu_status,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE NULL
    END AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hadm_id IN (
      -- Get admissions with sepsis diagnosis (excluding septic shock)
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        -- ICD-9 codes for sepsis (excluding septic shock)
        (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92') AND d.icd_code != '785.52')
        OR
        -- ICD-10 codes for sepsis (excluding septic shock)
        (d.icd_version = 10 AND d.icd_code IN ('R65.20', 'R65.21') AND d.icd_code != 'R65.22')
    )
)

SELECT
  los_category,
  day1_icu_status,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deceased_patients,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN days_to_death ELSE NULL END), 2) AS median_days_to_death
FROM sepsis_patients
GROUP BY los_category, day1_icu_status
ORDER BY los_category, day1_icu_status;