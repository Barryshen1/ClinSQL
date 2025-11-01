WITH pci_subjects AS (
  SELECT pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pi.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (LOWER(dip.long_title) LIKE '%pci%' OR LOWER(dip.long_title) LIKE '%angioplasty%')
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN pci_subjects ps ON i.hadm_id = ps.hadm_id;