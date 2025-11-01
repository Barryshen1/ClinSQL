WITH pci_admissions AS (
  -- Identify admissions with an ICD-coded procedure whose description looks like PCI.
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%percutaneous%'
    AND (
      LOWER(d.long_title) LIKE '%coronar%'    -- coronary / coronary artery
      OR LOWER(d.long_title) LIKE '%stent%'
      OR LOWER(d.long_title) LIKE '%transluminal%'
    )
)

SELECT
  a.subject_id,
  a.hadm_id,
  pt.anchor_age,
  pt.gender,
  a.admittime,
  COUNT(DISTINCT s.stay_id) AS icu_stay_count,
  MAX(s.los) AS max_icustay_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON a.subject_id = pt.subject_id
JOIN pci_admissions pci
  ON a.hadm_id = pci.hadm_id
JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
  ON a.hadm_id = s.hadm_id
WHERE pt.gender = 'F'
  AND pt.anchor_age BETWEEN 59 AND 69
GROUP BY a.subject_id, a.hadm_id, pt.anchor_age, pt.gender, a.admittime
ORDER BY max_icustay_los_days DESC;