SELECT STDDEV_SAMP(i.los) AS std_dev_icu_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON p.subject_id = d.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
JOIN physionet-data.mimiciv_3_1_icu.icustays i ON d.hadm_id = i.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND LOWER(dic.long_title) LIKE '%sepsis%'
  AND LOWER(dic.long_title) NOT LIKE '%neonatal%'  -- exclude neonatal sepsis if present
  AND LOWER(dic.long_title) NOT LIKE '%viral%'     -- optional: exclude viral sepsis if desired, but generally include
  AND LOWER(dic.long_title) NOT LIKE '%fungal%'    -- optional: include unless specified otherwise;