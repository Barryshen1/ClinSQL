WITH sepsis_patients AS (
  -- Identify male patients aged 87-97 with sepsis but no septic shock
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    -- Sepsis ICD codes (ICD-9 and ICD-10)
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('995.91', '785.52'))
      OR (d.icd_version = 10 AND d.icd_code IN ('R65.20', 'R65.21'))
    )
    -- Exclude septic shock
    AND NOT (
      (d.icd_version = 9 AND d.icd_code = '785.52')
      OR (d.icd_version = 10 AND d.icd_code = 'R65.21')
    )
    -- Only include completed admissions
    AND a.dischtime IS NOT NULL
),

diagnostic_procedures AS (
  -- Count diagnostic procedures per admission
  SELECT
    sp.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_diagnostic_procedures
  FROM
    sepsis_patients sp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  ON
    sp.subject_id = p.subject_id AND sp.hadm_id = p.hadm_id
  WHERE
    -- Filter for diagnostic procedures (this is a simplified approach)
    -- In practice, you might need a more comprehensive list of diagnostic procedure codes
    p.icd_code LIKE '8%'  -- ICD-9 diagnostic procedures typically start with 8
    OR p.icd_code LIKE '9%'  -- Some diagnostic procedures start with 9
    OR p.icd_code LIKE '0%'  -- Some diagnostic procedures start with 0
  GROUP BY
    sp.hadm_id
)

-- Calculate mean diagnostic procedures by admission duration
SELECT
  CASE
    WHEN sp.admission_duration_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN sp.admission_duration_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other duration'
  END AS admission_duration_category,
  AVG(dp.num_diagnostic_procedures) AS mean_diagnostic_procedures,
  COUNT(*) AS number_of_admissions
FROM
  sepsis_patients sp
LEFT JOIN
  diagnostic_procedures dp
ON
  sp.hadm_id = dp.hadm_id
WHERE
  sp.admission_duration_days BETWEEN 1 AND 7
GROUP BY
  admission_duration_category
ORDER BY
  admission_duration_category;