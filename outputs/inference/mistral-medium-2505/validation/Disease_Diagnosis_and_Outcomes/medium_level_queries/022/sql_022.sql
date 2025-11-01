WITH sepsis_patients AS (
  -- Identify male patients aged 50-60 with sepsis (not septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check if patient was in ICU within first 24 hours
    MAX(CASE WHEN TIMESTAMP_DIFF(t.intime, a.admittime, HOUR) <= 24 THEN 1 ELSE 0 END) AS day1_icu
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` t ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  WHERE
    p.gender = 'M'
    -- Calculate age at admission (anchor_age is age at some anchor year)
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
    -- Sepsis ICD codes (excluding septic shock)
    AND (
      (di.icd_code LIKE 'A41.%' AND di.icd_code NOT LIKE 'A41.9')  -- Other sepsis
      OR di.icd_code LIKE 'R65.2%'  -- Severe sepsis
      OR di.icd_code LIKE 'A40.%'    -- Streptococcal sepsis
      OR di.icd_code LIKE 'A42.%'    -- Actinomycotic sepsis
    )
    -- Exclude septic shock (R65.21, A41.9, etc.)
    AND di.icd_code NOT IN ('R65.21', 'A41.9', 'R57.2')
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, los_days
),

patient_groups AS (
  -- Group patients by LOS and ICU status
  SELECT
    CASE WHEN los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_group,
    CASE WHEN day1_icu = 1 THEN 'ICU on day 1' ELSE 'No ICU on day 1' END AS icu_status,
    COUNT(*) AS patient_count,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_percentage,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM
    sepsis_patients
  GROUP BY
    los_group, icu_status
)

-- Final output
SELECT
  los_group,
  icu_status,
  patient_count,
  deaths,
  mortality_percentage,
  median_los
FROM
  patient_groups
ORDER BY
  los_group, icu_status;