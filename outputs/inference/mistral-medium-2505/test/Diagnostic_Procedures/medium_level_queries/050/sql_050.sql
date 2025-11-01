WITH
-- Get male patients aged 90-100
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),

-- Get admissions with stay duration categories
admissions_with_duration AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS stay_duration_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    a.dischtime IS NOT NULL
),

-- Count imaging procedures per admission
imaging_counts AS (
  SELECT
    a.hadm_id,
    a.stay_duration_category,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_procedure_count
  FROM
    admissions_with_duration a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON a.hadm_id = h.hadm_id
  WHERE
    h.short_description LIKE '%XRAY%'
    OR h.short_description LIKE '%CT%'
    OR h.short_description LIKE '%MRI%'
    OR h.short_description LIKE '%ULTRASOUND%'
    OR h.short_description LIKE '%SCAN%'
    OR h.short_description LIKE '%RADIOLOGY%'
  GROUP BY
    a.hadm_id, a.stay_duration_category
)

-- Calculate statistics by stay duration category
SELECT
  stay_duration_category,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(imaging_procedure_count) AS mean_imaging_procedures,
  MIN(imaging_procedure_count) AS min_imaging_procedures,
  MAX(imaging_procedure_count) AS max_imaging_procedures
FROM
  imaging_counts
WHERE
  stay_duration_category IS NOT NULL
GROUP BY
  stay_duration_category
ORDER BY
  stay_duration_category;