WITH sepsis_codes AS (
  -- ICD-9 and ICD-10 codes for sepsis
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10
),
septic_shock_codes AS (
  -- ICD-9 and ICD-10 codes for septic shock
  SELECT '78552' AS icd_code, 9 AS icd_version UNION ALL
  SELECT 'R6521', 10
),
cohort AS (
  -- Men aged 52-62
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
admission_sepsis AS (
  -- For each admission, determine if sepsis and/or septic shock is present
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.admission_type,
    c.hospital_expire_flag,
    -- Sepsis present if any sepsis code
    MAX(CASE WHEN s.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_sepsis,
    -- Septic shock present if any septic shock code
    MAX(CASE WHEN ss.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_septic_shock
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
    LEFT JOIN sepsis_codes s
      ON d.icd_code LIKE CONCAT(s.icd_code, '%') AND d.icd_version = s.icd_version
    LEFT JOIN septic_shock_codes ss
      ON d.icd_code LIKE CONCAT(ss.icd_code, '%') AND d.icd_version = ss.icd_version
  GROUP BY
    c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.admittime, c.dischtime, c.admission_type, c.hospital_expire_flag
),
sepsis_cohort AS (
  -- Only admissions with sepsis
  SELECT
    *,
    CASE
      WHEN has_septic_shock = 1 THEN 'Septic shock'
      WHEN has_sepsis = 1 THEN 'No shock'
      ELSE NULL
    END AS sepsis_severity,
    -- Calculate LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days
  FROM
    admission_sepsis
  WHERE
    has_sepsis = 1
),
los_bins AS (
  -- Bin LOS
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE NULL
    END AS los_bin
  FROM
    sepsis_cohort
  WHERE
    los_days IS NOT NULL
),
comorbidity_count AS (
  -- For each admission, count unique comorbidities (excluding sepsis/septic shock codes)
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    los_bins l
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON l.hadm_id = d.hadm_id
    LEFT JOIN sepsis_codes s
      ON d.icd_code LIKE CONCAT(s.icd_code, '%') AND d.icd_version = s.icd_version
    LEFT JOIN septic_shock_codes ss
      ON d.icd_code LIKE CONCAT(ss.icd_code, '%') AND d.icd_version = ss.icd_version
  WHERE
    s.icd_code IS NULL
    AND ss.icd_code IS NULL
  GROUP BY
    l.subject_id, l.hadm_id
),
final AS (
  -- Combine everything
  SELECT
    l.sepsis_severity,
    l.los_bin,
    l.admission_type,
    l.hospital_expire_flag,
    c.comorbidity_count
  FROM
    los_bins l
    LEFT JOIN comorbidity_count c
      ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE
    l.sepsis_severity IS NOT NULL
    AND l.los_bin IS NOT NULL
    AND l.admission_type IS NOT NULL
)
SELECT
  sepsis_severity,
  los_bin,
  admission_type,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_percent,
  ROUND(AVG(comorbidity_count), 2) AS mean_comorbidity_count
FROM
  final
GROUP BY
  sepsis_severity,
  los_bin,
  admission_type
ORDER BY
  sepsis_severity,
  los_bin,
  admission_type;