WITH
-- Get male patients aged 58-68
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),

-- Get their admissions with LOS calculation
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    a.dischtime IS NOT NULL  -- Only completed admissions
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7  -- LOS 1-7 days
),

-- Categorize admissions by LOS groups
los_groups AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM
    admissions_with_los
),

-- Get radiography/CT procedures (using HCPCS codes)
radiology_procedures AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE
    (d.long_description LIKE '%RADIOLOGY%'
     OR d.long_description LIKE '%CT%'
     OR d.short_description LIKE '%RADIOLOGY%'
     OR d.short_description LIKE '%CT%')
  GROUP BY
    h.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    l.los_group,
    COUNT(DISTINCT a.subject_id) AS patient_count,
    COUNT(DISTINCT l.hadm_id) AS admission_count,
    AVG(COALESCE(r.procedure_count, 0)) AS mean_procedures_per_admission
  FROM
    los_groups l
  JOIN
    admissions_with_los a ON l.hadm_id = a.hadm_id
  LEFT JOIN
    radiology_procedures r ON l.hadm_id = r.hadm_id
  GROUP BY
    l.los_group
)

-- Final output
SELECT
  los_group,
  patient_count,
  admission_count,
  ROUND(mean_procedures_per_admission, 2) AS mean_procedures_per_admission
FROM
  final_data
ORDER BY
  los_group;