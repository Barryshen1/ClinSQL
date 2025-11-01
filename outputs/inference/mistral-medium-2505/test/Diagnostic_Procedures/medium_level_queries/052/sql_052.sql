WITH
-- Get female patients aged 73-83
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 73 AND 83
),

-- Get relevant admissions with LOS calculation
relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.admission_type = 'EMERGENCY' THEN 'ED'
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE 'Other'
    END AS admission_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Identify ultrasound procedures (using HCPCS codes)
ultrasound_procedures AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE
    -- Common ultrasound HCPCS codes (this may need adjustment based on actual data)
    h.hcpcs_cd IN (
      '76700', '76705', '76770', '76775', '76801', '76802', '76810', '76811',
      '76815', '76816', '76817', '76820', '76821', '76825', '76826', '76827',
      '76828', '76830', '76856', '76857', '76870', '76872', '76881', '76882',
      '76937', '76942', '76945', '76946', '76970', '76975', '76977', '76981',
      '76982', '76985', '76999', '93303', '93304', '93306', '93307', '93308',
      '93312', '93313', '93314', '93315', '93316', '93317', '93318', '93320',
      '93321', '93325', '93350', '93351', '93352'
    )
    OR
    -- Additional filter for echocardiogram-related procedures
    LOWER(d.short_description) LIKE '%echo%'
    OR LOWER(d.short_description) LIKE '%ultrasound%'
  GROUP BY
    h.subject_id, h.hadm_id
),

-- Combine all data with ultrasound counts (including 0 counts)
admission_stats AS (
  SELECT
    r.hadm_id,
    r.admission_category,
    CASE
      WHEN r.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN r.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_category,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM
    relevant_admissions r
  LEFT JOIN
    ultrasound_procedures u ON r.hadm_id = u.hadm_id
)

-- Final aggregation
SELECT
  admission_category,
  los_category,
  COUNT(hadm_id) AS admission_count,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM
  admission_stats
GROUP BY
  admission_category, los_category
ORDER BY
  admission_category, los_category;