WITH
-- Get male patients aged 76-86
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get AMI admissions (ICD-10 codes I21.x, I22.x)
ami_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'
    AND d.icd_version = 10
),

-- Get Troponin I lab events (LOINC code 10839-9) for AMI patients
troponin_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS lab_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  JOIN
    ami_admissions a
  ON
    l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    d.loinc_code = '10839-9'
    AND l.valuenum IS NOT NULL
),

-- Get first Troponin I measurement per admission
first_troponin AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.valuenum AS troponin_value
  FROM
    troponin_labs t
  WHERE
    t.lab_rank = 1
),

-- Calculate overall statistics for percentile calculations
overall_stats AS (
  SELECT
    PERCENTILE_CONT(troponin_value, 0.25) OVER() AS q1,
    PERCENTILE_CONT(troponin_value, 0.5) OVER() AS median,
    PERCENTILE_CONT(troponin_value, 0.75) OVER() AS q3,
    COUNT(*) OVER() AS total_count
  FROM
    first_troponin
  LIMIT 1
)

-- Final analysis
SELECT
  CASE
    WHEN troponin_value <= 0.04 THEN 'Normal (≤0.04)'
    WHEN troponin_value > 0.04 AND troponin_value <= 0.40 THEN 'Borderline (0.04–0.40)'
    WHEN troponin_value > 0.40 THEN 'Elevated (≥0.40)'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / (SELECT total_count FROM overall_stats), 2) AS percentage,
  ROUND(AVG(troponin_value), 4) AS mean_value,
  ROUND((SELECT median FROM overall_stats), 4) AS median_value,
  ROUND((SELECT q1 FROM overall_stats), 4) AS q1_value,
  ROUND((SELECT q3 FROM overall_stats), 4) AS q3_value,
  ROUND((SELECT q3 FROM overall_stats) - (SELECT q1 FROM overall_stats), 4) AS iqr
FROM
  first_troponin f
JOIN
  ami_admissions a
ON
  f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal (≤0.04)' THEN 1
    WHEN 'Borderline (0.04–0.40)' THEN 2
    WHEN 'Elevated (≥0.40)' THEN 3
    ELSE 4
  END;