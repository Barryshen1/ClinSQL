WITH
-- Get male patients aged 79-89
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
),

-- Get their admissions with suspected ACS
acs_admissions AS (
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
    eligible_patients p
    ON a.subject_id = p.subject_id
  WHERE
    -- ACS ICD codes (ICD-9 and ICD-10)
    (d.icd_code LIKE 'I20.0%' OR
     d.icd_code LIKE 'I21.%' OR
     d.icd_code LIKE 'I22.%' OR
     d.icd_code LIKE 'I24.%' OR
     d.icd_code LIKE '410.%' OR
     d.icd_code LIKE '411.1%')
),

-- Get first troponin T measurement within 24 hours of admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) as rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    acs_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    -- Troponin T itemid (may need adjustment based on actual data)
    di.label = 'Troponin T'
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL
),

-- Get only the first measurement per admission
clean_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM
    first_troponin
  WHERE
    rn = 1
),

-- Categorize troponin levels
troponin_categories AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 0.01 THEN 'Normal'
      WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
      WHEN valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS category
  FROM
    clean_troponin
)

-- Final analysis
SELECT
  category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean_troponin,
  ROUND(PERCENTILE_CONT(valuenum, 0.5) OVER (PARTITION BY category), 4) AS median_troponin,
  ROUND(PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY category), 4) AS q1_troponin,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY category), 4) AS q3_troponin,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY category) -
        PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY category), 4) AS iqr_troponin
FROM
  troponin_categories
GROUP BY
  category, valuenum
ORDER BY
  category;