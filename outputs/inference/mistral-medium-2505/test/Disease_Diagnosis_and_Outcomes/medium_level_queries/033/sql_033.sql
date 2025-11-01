WITH
-- Get male patients aged 82-92
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 82 AND 92
),

-- Get admissions with postoperative complications
postop_complications AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        a.subject_id = d.subject_id
        AND a.hadm_id = d.hadm_id
        AND (d.icd_code LIKE 'T8%' OR d.icd_code LIKE 'K91%')
    )
),

-- Count comorbidities (excluding postoperative complications)
comorbidity_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code NOT LIKE 'T8%'
    AND d.icd_code NOT LIKE 'K91%'
    AND d.icd_code NOT LIKE 'E%'  -- Exclude external causes
    AND d.icd_code NOT LIKE 'V%'  -- Exclude supplementary codes
    AND d.icd_code NOT LIKE 'Y%'  -- Exclude external causes
    AND d.icd_code NOT LIKE 'Z%'  -- Exclude factors influencing health status
  GROUP BY
    subject_id, hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icu_status,
    p.los_days,
    CASE WHEN p.los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category,
    CASE
      WHEN c.comorbidity_count BETWEEN 0 AND 1 THEN '0-1'
      WHEN c.comorbidity_count = 2 THEN '2'
      ELSE '≥3'
    END AS comorbidity_bin,
    p.hospital_expire_flag,
    c.comorbidity_count
  FROM
    postop_complications p
  JOIN
    comorbidity_counts c ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
)

-- Final aggregation
SELECT
  icu_status,
  los_category,
  comorbidity_bin,
  COUNT(DISTINCT subject_id) AS N,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id), 1) AS mortality_percentage,
  ROUND(AVG(comorbidity_count), 1) AS avg_comorbidity_count
FROM
  combined_data
GROUP BY
  icu_status, los_category, comorbidity_bin
ORDER BY
  icu_status, los_category, comorbidity_bin;