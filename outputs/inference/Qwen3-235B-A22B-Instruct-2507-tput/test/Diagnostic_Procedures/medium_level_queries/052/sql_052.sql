WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
ultrasound_procs AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ultrasound%'
     OR LOWER(d.short_description) LIKE '%echocardiogram%'
     OR LOWER(d.short_description) LIKE '%echo%'
     OR h.hcpcs_cd IN ('93306', '93307', '76828', '76830', '76700', '76705')
  GROUP BY h.hadm_id
),
admission_summary AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    pa.admission_type,
    COALESCE(up.ultrasound_count, 0) AS ultrasound_count,
    CASE
      WHEN pa.los_days > 0 AND pa.los_days <= 3 THEN '1-3 days'
      WHEN pa.los_days > 3 AND pa.los_days <= 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN pa.admission_type = 'ELECTIVE' THEN 'Elective'
      WHEN pa.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED'
      ELSE NULL
    END AS admission_category
  FROM patient_admissions pa
  LEFT JOIN ultrasound_procs up ON pa.hadm_id = up.hadm_id
  WHERE pa.los_days > 0 AND pa.los_days <= 7
),
grouped_stats AS (
  SELECT
    los_group,
    admission_category,
    AVG(ultrasound_count) AS mean_ultrasounds,
    MIN(ultrasound_count) AS min_ultrasounds,
    MAX(ultrasound_count) AS max_ultrasounds
  FROM admission_summary
  WHERE los_group IS NOT NULL AND admission_category IS NOT NULL
  GROUP BY los_group, admission_category
)
SELECT
  los_group,
  admission_category,
  ROUND(mean_ultrasounds, 2) AS mean_ultrasounds,
  min_ultrasounds,
  max_ultrasounds
FROM grouped_stats
ORDER BY los_group, admission_category;