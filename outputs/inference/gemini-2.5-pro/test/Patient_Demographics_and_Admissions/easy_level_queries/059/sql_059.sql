WITH pci_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    -- ICD-9 codes for PTCA (00.66) and coronary stent insertion (36.06, 36.07)
    (icd_version = 9 AND icd_code IN ('0066', '3606', '3607'))
    OR
    -- ICD-10-PCS codes for dilation of coronary arteries (root '027'), which includes PCI.
    (icd_version = 10 AND icd_code LIKE '027%')
)
-- Main query to join patient demographics, PCI encounters, and ICU stay data.
SELECT
  pat.subject_id,
  icu.hadm_id,
  MAX(icu.los) AS max_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
-- Join with patients to filter by demographics
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icu.subject_id = pat.subject_id
-- Join with PCI admissions to ensure the procedure was performed during the hospital stay
INNER JOIN pci_admissions AS pci
  ON icu.hadm_id = pci.hadm_id
WHERE
  -- 1. Filter for female patients
  pat.gender = 'F'
  -- 2. Filter for patients aged 59-69 using anchor_age
  AND pat.anchor_age BETWEEN 59 AND 69
-- Group by patient and hospital admission to find the max ICU stay per encounter
GROUP BY
  pat.subject_id,
  icu.hadm_id
-- Order results to show the longest stays first
ORDER BY
  max_icu_los_days DESC,
  subject_id;