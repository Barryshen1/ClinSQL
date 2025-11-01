SELECT
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  ON adm.hadm_id = proc.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_procedures d_proc
  ON proc.icd_code = d_proc.icd_code
  AND proc.icd_version = d_proc.icd_version
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 68 AND 78
  AND (
    LOWER(d_proc.long_title) LIKE '%percutaneous coronary intervention%'
    OR LOWER(d_proc.long_title) LIKE '%pci%'
  );