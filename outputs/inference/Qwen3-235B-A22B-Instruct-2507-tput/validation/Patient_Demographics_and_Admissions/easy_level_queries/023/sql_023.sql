SELECT
  APPROX_QUANTILES(icu.los, 100)[OFFSET(50)] AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON p.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
  ON adm.hadm_id = proc.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  p.gender = 'M'
  AND proc.icd_version = 10
  AND proc.icd_code LIKE '021%'  -- ICD-10-PCS codes for coronary interventions (PCI)
  AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 68 AND 78
  AND icu.los IS NOT NULL;