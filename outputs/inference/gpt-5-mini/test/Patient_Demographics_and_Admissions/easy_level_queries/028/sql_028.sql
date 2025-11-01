SELECT
  STDDEV_SAMP(icu.los) AS icu_los_sd_days,
  COUNT(DISTINCT icu.stay_id) AS n_stays
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND icu.los IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON dx.icd_code = dicd.icd_code
      AND dx.icd_version = dicd.icd_version
    WHERE dx.hadm_id = icu.hadm_id
      AND (
        LOWER(COALESCE(dicd.long_title, '')) LIKE '%sepsis%'
        OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%septic%'
      )
  );