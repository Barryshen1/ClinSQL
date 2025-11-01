WITH
-- Get male patients aged 80-90
eligible_patients AS (
  SELECT
    subject_id,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),

-- Get admissions with ACS diagnosis
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
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25')  -- ACS ICD-10 codes
    AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS measurement_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T, High Sensitivity'
    AND l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND l.valuenum IS NOT NULL
)

-- Final aggregation
SELECT
  CASE
    WHEN f.valuenum < 14 THEN 'Normal'
    WHEN f.valuenum BETWEEN 14 AND 50 THEN 'Borderline'
    WHEN f.valuenum > 50 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS hs_tnt_category,
  COUNT(DISTINCT f.hadm_id) AS patient_count,
  ROUND(COUNT(DISTINCT f.hadm_id) * 100.0 / SUM(COUNT(DISTINCT f.hadm_id)) OVER(), 2) AS percentage,
  ROUND(AVG(a.length_of_stay_days), 2) AS mean_length_of_stay_days
FROM
  first_hs_tnt f
JOIN
  acs_admissions a
  ON f.hadm_id = a.hadm_id
WHERE
  f.measurement_rank = 1  -- Only first measurement per admission
GROUP BY
  hs_tnt_category
ORDER BY
  patient_count DESC;