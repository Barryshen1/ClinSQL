WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    -- Include sepsis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d_icd.icd_code = dd.icd_code
       AND d_icd.icd_version = dd.icd_version
      WHERE d_icd.hadm_id = a.hadm_id
        AND (
          dd.long_title LIKE '%Sepsis%'
          OR dd.icd_code LIKE 'A40%'
          OR dd.icd_code LIKE 'A41%'
          OR dd.icd_code LIKE '038%'
          OR dd.icd_code IN ('99591','99592')
        )
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d_icd.icd_code = dd.icd_code
       AND d_icd.icd_version = dd.icd_version
      WHERE d_icd.hadm_id = a.hadm_id
        AND (
          dd.long_title LIKE '%septic shock%'
          OR d_icd.icd_code IN ('R6521','78552')
        )
    )
),
icu_day1 AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    CASE WHEN MIN(TIMESTAMP_DIFF(i.intime, s.admittime, HOUR)) <= 24
         AND MIN(TIMESTAMP_DIFF(i.intime, s.admittime, HOUR)) >= 0
         THEN 'Yes' ELSE 'No' END AS day1_icu
  FROM sepsis_admissions s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON s.hadm_id = i.hadm_id
  GROUP BY s.subject_id, s.hadm_id
),
final AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    DATE_DIFF(DATE(s.dischtime), DATE(s.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(s.dischtime), DATE(s.admittime), DAY) <= 3 THEN '≤3'
      WHEN DATE_DIFF(DATE(s.dischtime), DATE(s.admittime), DAY) BETWEEN 4 AND 6 THEN '4–6'
      WHEN DATE_DIFF(DATE(s.dischtime), DATE(s.admittime), DAY) BETWEEN 7 AND 10 THEN '7–10'
      WHEN DATE_DIFF(DATE(s.dischtime), DATE(s.admittime), DAY) > 10 THEN '>10'
    END AS los_bin,
    i.day1_icu,
    s.hospital_expire_flag,
    CASE WHEN s.hospital_expire_flag = 1
         THEN DATE_DIFF(DATE(s.deathtime), DATE(s.admittime), DAY)
         ELSE NULL END AS days_to_death
  FROM sepsis_admissions s
  JOIN icu_day1 i
    ON s.subject_id = i.subject_id
   AND s.hadm_id = i.hadm_id
)
SELECT
  los_bin,
  day1_icu,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percent,
  APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death
FROM final
GROUP BY los_bin, day1_icu
ORDER BY
  CASE los_bin
    WHEN '≤3' THEN 1
    WHEN '4–6' THEN 2
    WHEN '7–10' THEN 3
    WHEN '>10' THEN 4
  END,
  day1_icu;