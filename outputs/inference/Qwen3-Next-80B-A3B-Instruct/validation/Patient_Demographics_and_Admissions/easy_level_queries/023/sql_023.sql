SELECT APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd proc ON p.subject_id = proc.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d_proc ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
JOIN physionet-data.mimiciv_3_1_icu.icustays icu ON proc.hadm_id = icu.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 68 AND 78
  AND (
    d_proc.long_title LIKE '%PCI%'
    OR d_proc.long_title LIKE '%percutaneous coronary intervention%'
    OR d_proc.long_title LIKE '%coronary angioplasty%'
    OR d_proc.long_title LIKE '%stent%'
    OR d_proc.long_title LIKE '%angioplasty%'
  );