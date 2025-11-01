WITH patient_birth AS (
  SELECT
    subject_id,
    DATE(anchor_year, 1, 1) AS anchor_date,  -- Create valid date from year
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE 
    anchor_year IS NOT NULL 
    AND anchor_age IS NOT NULL 
    AND anchor_year BETWEEN 2008 AND 2019  -- Exclude outliers
),
admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.admittime, p.anchor_date, YEAR) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_birth p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT
    awa.*
  FROM admissions_with_age awa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
      awa.subject_id = d.subject_id 
      AND awa.hadm_id = d.hadm_id
      AND d.icd_version = 10
      AND dd.long_title LIKE '%hemorrhage%'  -- Validate codes via descriptions
  )
),
filtered_admissions AS (
  SELECT *
  FROM hemorrhagic_stroke_admissions
  WHERE age BETWEEN 80 AND 90
    AND los BETWEEN 1 AND 7
),
ultrasound_counts AS (
  SELECT
    f.hadm_id,
    COUNT(DISTINCT p.seq_num) AS ultrasound_count
  FROM filtered_admissions f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
    AND p.icd_version = 9
    AND p.icd_code IN ('93.91', '93.92', '93.93', '93.94', '93.95', '93.96', '93.97', '93.98', '93.99')
  GROUP BY f.hadm_id
)
SELECT
  CASE
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  COUNT(ultrasound_count) AS num_admissions,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM filtered_admissions f
LEFT JOIN ultrasound_counts u ON f.hadm_id = u.hadm_id
GROUP BY los_group
ORDER BY los_group;