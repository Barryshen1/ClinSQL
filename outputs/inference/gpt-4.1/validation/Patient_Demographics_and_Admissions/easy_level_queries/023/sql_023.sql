WITH pci_procedures AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    -- ICD-9-CM PCI codes
    (icd_version = 9 AND (
      icd_code IN ('36.06', '36.07', '36.09', '00.66')
    ))
    -- ICD-10-PCS PCI codes (starts with 02703, 02713, 02723, 02733)
    OR (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^0270[3-4][0-9]$') OR
      REGEXP_CONTAINS(icd_code, r'^0271[3-4][0-9]$') OR
      REGEXP_CONTAINS(icd_code, r'^0272[3-4][0-9]$') OR
      REGEXP_CONTAINS(icd_code, r'^0273[3-4][0-9]$')
    ))
)
SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM (
  SELECT
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    pci_procedures pci
    ON icu.subject_id = pci.subject_id
    AND icu.hadm_id = pci.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
);