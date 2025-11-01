WITH patient_selection AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
),
pci_patients AS (
  SELECT DISTINCT p.subject_id
  FROM patient_selection p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON p.subject_id = proc.subject_id
  WHERE proc.icd_code IN (
    '02703ZZ', '02704ZZ', '02713ZZ', '02714ZZ', '02723ZZ', '02724ZZ', 
    '00.66', '36.01', '36.02', '36.05', '36.06', '36.07'
  )
),
icu_los AS (
  SELECT i.stay_id, DATETIME_DIFF(i.outtime, i.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN pci_patients p ON i.subject_id = p.subject_id
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_icu_los
FROM icu_los;