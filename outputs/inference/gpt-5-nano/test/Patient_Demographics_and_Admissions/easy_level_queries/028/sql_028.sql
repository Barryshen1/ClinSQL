SELECT STDDEV_SAMP(i.los) AS icu_los_sd_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON i.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
WHERE p.gender = 'Male'
  AND p.anchor_age BETWEEN 90 AND 100
  AND LOWER(dd.long_title) LIKE '%sepsis%'
  -- Optional: exclude zero or NULL LOS if necessary
  AND i.los IS NOT NULL;