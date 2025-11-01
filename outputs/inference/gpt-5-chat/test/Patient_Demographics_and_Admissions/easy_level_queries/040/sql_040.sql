SELECT 
  percentile_cont(los, 0.5) OVER() AS median_icu_los_days
FROM (
  SELECT DISTINCT icu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code
   AND dx.icd_version = ddx.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.subject_id = icu.subject_id
   AND adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND LOWER(ddx.long_title) LIKE '%stroke%'
) ;