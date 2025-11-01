SELECT
  APPROX_QUANTILES(i.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON i.subject_id = adm.subject_id
  AND i.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  ON adm.hadm_id = proc.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
  ON proc.icd_code = dproc.icd_code
  AND proc.icd_version = dproc.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 68 AND 78
  AND LOWER(dproc.long_title) LIKE '%percutaneous coronary intervention%';