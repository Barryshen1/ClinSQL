WITH septic_shock_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code = 'R65.21'
        AND d.icd_version = 10
    )
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE short_description LIKE '%ultrasound%' OR short_description LIKE '%echo%'
    UNION ALL
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON p.itemid = d.itemid
    WHERE d.label LIKE '%ultrasound%' OR d.label LIKE '%echo%'
  ) AS all_ultrasound
  GROUP BY hadm_id
),
icu_status AS (
  SELECT hadm_id, 
         CASE WHEN COUNT(*) > 0 THEN 'ICU' ELSE 'No ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
admissions_with_data AS (
  SELECT 
    s.hadm_id,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count,
    TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
    i.icu_status
  FROM septic_shock_admissions s
  LEFT JOIN ultrasound_counts u ON s.hadm_id = u.hadm_id
  LEFT JOIN icu_status i ON s.hadm_id = i.hadm_id
  WHERE TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) BETWEEN 1 AND 7
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
  END AS los_group,
  icu_status,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ultrasound_count) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ultrasound_count) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ultrasound_count) AS p75
FROM admissions_with_data
GROUP BY los_group, icu_status;