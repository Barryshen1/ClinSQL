WITH pci_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE diag.icd_version = 1  -- Focus on ICD-10 for modern PCI codes
    AND diag.icd_code LIKE '00.4%'  -- Percutaneous coronary interventions (ICD-10)
),
qualified_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN pci_admissions pca
    ON a.hadm_id = pca.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
)
SELECT 
  MAX(los) AS max_icu_los_days
FROM qualified_stays;