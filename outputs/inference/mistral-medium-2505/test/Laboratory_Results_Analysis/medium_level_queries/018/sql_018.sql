WITH
-- Get male patients aged 90-100
elderly_male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 90 AND 100
),

-- Get ACS admissions (using common ICD-10 codes for ACS)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM elderly_male_patients)
    AND (
      -- ICD-10 codes for ACS
      (d.icd_version = 10 AND d.icd_code IN (
        'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
        'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9', 'I24.0', 'I24.8', 'I24.9'
      ))
      -- ICD-9 codes for ACS (if needed)
      OR (d.icd_version = 9 AND d.icd_code IN (
        '410.00', '410.01', '410.02', '410.10', '410.11', '410.12',
        '410.20', '410.21', '410.22', '410.30', '410.31', '410.32',
        '410.40', '410.41', '410.42', '410.50', '410.51', '410.52',
        '410.60', '410.61', '410.62', '410.70', '410.71', '410.72',
        '410.80', '410.81', '410.82', '410.90', '410.91', '410.92'
      ))
    )
),

-- Get first Troponin T measurement for each admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND d.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
),

-- Categorize Troponin T levels
troponin_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN valuenum < 0.01 THEN 'Normal'
      WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
      WHEN valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    first_troponin
  WHERE
    rn = 1  -- Only first measurement per admission
),

-- Combine all data
final_data AS (
  SELECT
    a.hadm_id,
    t.troponin_category,
    a.length_of_stay_days
  FROM
    acs_admissions a
  JOIN
    troponin_categories t ON a.hadm_id = t.hadm_id
)

-- Final aggregation
SELECT
  troponin_category,
  COUNT(hadm_id) AS patient_count,
  ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage,
  ROUND(AVG(length_of_stay_days), 2) AS mean_length_of_stay_days
FROM
  final_data
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;