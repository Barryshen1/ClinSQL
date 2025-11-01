SELECT MAX(i.los) AS max_icu_los
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  ON p.subject_id = pi.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
  ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
JOIN physionet-data.mimiciv_3_1_icu.icustays i
  ON pi.hadm_id = i.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND (
    LOWER(dip.long_title) LIKE '%pci%'
    OR LOWER(dip.long_title) LIKE '%percutaneous coronary intervention%'
    OR LOWER(dip.long_title) LIKE '%coronary angioplasty%'
  );