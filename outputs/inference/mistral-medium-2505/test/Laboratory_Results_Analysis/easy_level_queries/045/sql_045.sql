WITH sepsis_admissions AS (
  -- Identify sepsis admissions for male patients aged 83
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 83
    AND (
      -- ICD-9 codes for sepsis
      (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92'))
      OR
      -- ICD-10 codes for sepsis
      (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'R65.20', 'R65.21', 'R65.22'))
    )
),

creatinine_values AS (
  -- Get creatinine values for these admissions
  SELECT
    sa.subject_id,
    sa.hadm_id,
    l.valuenum AS creatinine
  FROM
    sepsis_admissions sa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON sa.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE
    dl.label = 'Creatinine'
    AND l.valuenum IS NOT NULL
)

-- Find the maximum creatinine per admission
SELECT
  subject_id,
  hadm_id,
  MAX(creatinine) AS max_creatinine
FROM
  creatinine_values
GROUP BY
  subject_id, hadm_id
ORDER BY
  max_creatinine DESC
LIMIT 10;  -- Limit to top 10 for brevity;