WITH pci_admissions AS (
  -- First, identify all hospital admissions (hadm_id) that involved a PCI procedure.
  -- We check for both ICD-9 and ICD-10 procedure codes related to PCI.
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    -- ICD-9 codes for PCI (Angioplasty and Stenting)
    (
      icd_version = 9 AND icd_code IN (
        '00.66', -- Percutaneous transluminal coronary angioplasty [PTCA]
        '36.01', -- Single vessel PTCA or atherectomy without thrombolytic agent
        '36.02', -- Single vessel PTCA or atherectomy with thrombolytic agent
        '36.05', -- Multiple vessel PTCA or atherectomy
        '36.06', -- Insertion of coronary artery stent(s)
        '36.07'  -- Insertion of drug-eluting coronary artery stent(s)
      )
    ) OR
    -- ICD-10-PCS codes for PCI (Dilation of Coronary Arteries)
    (
      icd_version = 10 AND icd_code LIKE '027%'
    )
)
-- Now, calculate the median ICU LOS for the specific patient cohort.
SELECT
  -- Calculate the median (50th percentile) of the ICU length of stay.
  APPROX_QUANTILES(icu.los, 100)[OFFSET(50)] AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
-- Join to filter for ICU stays that occurred during a PCI admission.
INNER JOIN
  pci_admissions AS pci ON icu.hadm_id = pci.hadm_id
-- Join with patient demographics to filter by age and gender.
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON icu.subject_id = pat.subject_id
WHERE
  -- Apply demographic filters for the target cohort.
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 68 AND 78;