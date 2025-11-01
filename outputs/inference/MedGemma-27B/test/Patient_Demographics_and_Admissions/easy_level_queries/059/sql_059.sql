WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 64
),
PCI_Procedures AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%PCI%'
),
ICU_Stays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN PatientInfo AS pi
    ON ic.subject_id = pi.subject_id
  JOIN PCI_Procedures AS pci
    ON ic.subject_id = pci.subject_id
)
SELECT
  MAX(los) AS max_icu_los
FROM ICU_Stays;