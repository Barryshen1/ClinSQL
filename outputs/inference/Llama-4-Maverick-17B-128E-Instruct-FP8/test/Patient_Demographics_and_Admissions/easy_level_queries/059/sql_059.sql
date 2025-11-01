WITH pci_patients AS (
  SELECT DISTINCT proc.subject_id, proc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON proc.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
    AND proc.icd_code IN (
      SELECT icd_code 
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` 
      WHERE icd_version = 10 AND long_title LIKE '%Percutaneous coronary intervention%'
    )
    AND proc.icd_version = 10  -- Ensure ICD version matches
),
icu_stays AS (
  SELECT subject_id, hadm_id, stay_id, los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT MAX(los) AS max_icu_los
FROM icu_stays
WHERE hadm_id IN (SELECT hadm_id FROM pci_patients);