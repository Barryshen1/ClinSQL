WITH
-- Get male patients aged 41-51
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),

-- Get admissions with chest pain or AMI diagnoses
relevant_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- Chest pain ICD codes
      d.icd_code LIKE 'R07.%' OR
      d.icd_code LIKE 'I20.%' OR
      -- AMI ICD codes
      d.icd_code LIKE 'I21.%'
    )
),

-- Get first Troponin T measurement within 24 hours of admission
initial_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN
    relevant_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    d.label = 'Troponin T'
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
),

-- Get only the first measurement per admission
first_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value
  FROM
    initial_troponin
  WHERE
    rn = 1
),

-- Categorize Troponin T values
troponin_categories AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value,
    CASE
      WHEN troponin_value < 0.01 THEN 'Normal'
      WHEN troponin_value BETWEEN 0.01 AND 0.03 THEN 'Borderline'
      WHEN troponin_value > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    first_troponin
)

-- Final aggregation
SELECT
  troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(troponin_value), 4) AS mean_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.5) OVER (PARTITION BY troponin_category), 4) AS median_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.25) OVER (PARTITION BY troponin_category), 4) AS q1_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.75) OVER (PARTITION BY troponin_category), 4) AS q3_troponin,
  ROUND(PERCENTILE_CONT(troponin_value, 0.75) OVER (PARTITION BY troponin_category) -
        PERCENTILE_CONT(troponin_value, 0.25) OVER (PARTITION BY troponin_category), 4) AS iqr_troponin
FROM
  troponin_categories
GROUP BY
  troponin_category, troponin_value
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;