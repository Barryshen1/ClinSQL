WITH
-- Get male patients aged 78-88
male_patients_78_88 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),

-- Get pacemaker/ICD procedures (using ICD-10-PCS codes)
pacemaker_icd_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.icd_code,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- Filter for pacemaker/ICD procedures (ICD-10-PCS codes)
    -- Example codes (expand as needed):
    p.icd_code IN (
      '02HK33Z', '02HK03Z', '02H633Z', '02H603Z',
      '02HK3JZ', '02HK0JZ', '02H63JZ', '02H60JZ',
      '02HK3KZ', '02HK0KZ', '02H63KZ', '02H60KZ'
    )
    -- Or use a broader filter (e.g., LIKE '02H%' for implantable devices)
    -- p.icd_code LIKE '02H%' OR p.icd_code LIKE '02HK%'
),

-- Count distinct procedures per patient
procedure_counts AS (
  SELECT
    m.subject_id,
    COUNT(DISTINCT p.icd_code) AS num_pacemaker_icd_procedures
  FROM
    male_patients_78_88 m
  LEFT JOIN
    pacemaker_icd_procedures p
  ON
    m.subject_id = p.subject_id
  GROUP BY
    m.subject_id
)

-- Calculate the 25th percentile
SELECT
  PERCENTILE_CONT(procedure_counts.num_pacemaker_icd_procedures, 0.25) OVER() AS percentile_25
FROM
  procedure_counts
LIMIT 1;