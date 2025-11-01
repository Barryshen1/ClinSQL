WITH pci_patients AS (
  -- Identify female patients aged 59-69 with PCI procedures
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND proc.icd_code LIKE '0270%'  -- PCI procedures (ICD-10-PCS)
    AND proc.icd_version = 10  -- ICD-10
),

icu_los AS (
  -- Calculate ICU LOS for these patients
  SELECT
    p.hadm_id,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM
    pci_patients p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.hadm_id = i.hadm_id
  WHERE
    i.outtime IS NOT NULL  -- Exclude ongoing ICU stays
)

-- Get the maximum ICU LOS per encounter
SELECT
  hadm_id,
  MAX(icu_los_hours) AS max_icu_los_hours
FROM
  icu_los
GROUP BY
  hadm_id
ORDER BY
  max_icu_los_hours DESC;