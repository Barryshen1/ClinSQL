WITH pci_hadm AS (
  -- admissions with at least one ICD-coded procedure whose description likely indicates PCI
  SELECT DISTINCT
    pr.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE
    pr.hadm_id IS NOT NULL
    AND (
      -- require 'coronar' to focus on coronary procedures, combined with PCI-related keywords
      (LOWER(COALESCE(dp.long_title, '')) LIKE '%coronar%' 
       AND (
         LOWER(COALESCE(dp.long_title, '')) LIKE '%percut%'    -- percutaneous
         OR LOWER(COALESCE(dp.long_title, '')) LIKE '%angiopl%' -- angioplasty / angioplasty variants
         OR LOWER(COALESCE(dp.long_title, '')) LIKE '%stent%'
         OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ptca%'     -- PTCA abbreviation
         OR LOWER(COALESCE(dp.long_title, '')) LIKE '%balloon%'
       )
      )
      -- also include titles that explicitly mention PCI or percutaneous transluminal coronary
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%percutaneous transluminal coronary%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%pci%'
    )
),

filtered_icustays AS (
  -- ICU stays for male patients aged 68-78 in admissions that had PCI
  SELECT
    icu.*
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    pci_hadm ph
    ON icu.hadm_id = ph.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND icu.los IS NOT NULL
)

SELECT
  -- approximate median ICU LOS in days across ICU stays
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los_days,
  COUNT(*) AS n_icu_stays
FROM
  filtered_icustays;