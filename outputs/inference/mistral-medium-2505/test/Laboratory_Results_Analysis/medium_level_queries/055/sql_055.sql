WITH
-- Get female patients aged 81-91
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),

-- Get admissions for chest pain or AMI
relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- Chest pain ICD codes
      d.icd_code IN ('I209', 'R071', 'R072', 'R074', 'R079')
      OR
      -- AMI ICD codes
      (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    )
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
    AND di.label = 'High Sensitivity Troponin T'
    AND l.valuenum IS NOT NULL
)

-- Final aggregation
SELECT
  hs_tnt_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM (
  SELECT
    ra.hadm_id,
    ra.los_days,
    CASE
      WHEN f.valuenum < 14 THEN 'Normal (<14 ng/L)'
      WHEN f.valuenum BETWEEN 14 AND 19 THEN 'Borderline (14-19 ng/L)'
      WHEN f.valuenum >= 20 THEN 'Myocardial injury (≥20 ng/L)'
      ELSE 'Unknown'
    END AS hs_tnt_category
  FROM
    relevant_admissions ra
  LEFT JOIN
    first_hs_tnt f
    ON ra.hadm_id = f.hadm_id AND f.rn = 1
)
GROUP BY
  hs_tnt_category
ORDER BY
  CASE hs_tnt_category
    WHEN 'Normal (<14 ng/L)' THEN 1
    WHEN 'Borderline (14-19 ng/L)' THEN 2
    WHEN 'Myocardial injury (≥20 ng/L)' THEN 3
    ELSE 4
  END;