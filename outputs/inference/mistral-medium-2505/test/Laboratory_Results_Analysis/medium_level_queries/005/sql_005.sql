WITH
-- Get male patients aged 35-45
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 35 AND 45
),

-- Get admissions with chest pain or AMI
relevant_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- AMI codes (I21.*)
      d.icd_code LIKE 'I21%'
      -- Chest pain codes (R07.*)
      OR d.icd_code LIKE 'R07%'
    )
),

-- Get the first high-sensitivity troponin T measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
    AND d.label LIKE '%Troponin T%'
    AND d.label LIKE '%High Sensitivity%'
    AND l.valuenum IS NOT NULL
)

-- Final categorization and counting
SELECT
  CASE
    WHEN valuenum < 14 THEN 'Normal'
    WHEN valuenum BETWEEN 14 AND 50 THEN 'Borderline'
    WHEN valuenum > 50 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS count
FROM
  first_troponin
WHERE
  rn = 1  -- Only the first measurement per admission
GROUP BY
  troponin_category
ORDER BY
  count DESC;