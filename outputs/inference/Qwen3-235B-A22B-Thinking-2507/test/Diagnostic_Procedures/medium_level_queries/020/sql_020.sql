WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    -- Calculate age at admission (approximation per MIMIC guidelines)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm,
    -- Calculate LOS in full days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND a.dischtime IS NOT NULL  -- Exclude in-progress admissions
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 72 AND 82
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
icu_flag AS (
  SELECT
    b.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM base_admissions b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON b.hadm_id = i.hadm_id
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    d.long_description LIKE '%Diagnostic Radiology%'
    OR d.long_description LIKE '%Nuclear Medicine%'
    OR d.long_description LIKE '%Ultrasound%'
  GROUP BY h.hadm_id
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  icu_use,
  COUNT(*) AS admission_count,
  AVG(COALESCE(i.imaging_count, 0)) AS mean_imaging_procedures
FROM icu_flag b
LEFT JOIN imaging_counts i
  ON b.hadm_id = i.hadm_id
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;