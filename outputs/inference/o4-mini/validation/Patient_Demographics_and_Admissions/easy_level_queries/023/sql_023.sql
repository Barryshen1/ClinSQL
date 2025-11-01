SELECT
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.subject_id = proc.subject_id
    AND a.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id
    AND a.hadm_id = icu.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 68 AND 78
  AND LOWER(dproc.long_title) LIKE '%percutaneous%'
  AND LOWER(dproc.long_title) LIKE '%intervention%';