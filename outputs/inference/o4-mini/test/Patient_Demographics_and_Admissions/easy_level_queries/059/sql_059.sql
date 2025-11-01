WITH pci_admissions AS (
  -- Identify admissions with a PCI procedure
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%percutaneous%'
    AND LOWER(d.long_title) LIKE '%coronary%'
),

female_59_69 AS (
  -- Select female patients aged 59-69
  SELECT
    pat.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
),

pci_cohort AS (
  -- Intersection: female 59-69 AND had a PCI
  SELECT
    f.subject_id,
    f.hadm_id
  FROM
    female_59_69 f
    INNER JOIN pci_admissions p
      ON f.subject_id = p.subject_id
      AND f.hadm_id = p.hadm_id
)

-- For each hospital admission in our cohort, get the maximum ICU LOS
SELECT
  c.subject_id,
  c.hadm_id,
  MAX(s.los) AS max_icu_los_days
FROM
  pci_cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    ON c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
GROUP BY
  c.subject_id,
  c.hadm_id
ORDER BY
  max_icu_los_days DESC;