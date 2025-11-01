SELECT
  COUNT(DISTINCT a.hadm_id) AS admissions_in_cohort
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON a.subject_id = di.subject_id
  AND a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON di.icd_code = dd.icd_code
  AND di.icd_version = dd.icd_version
WHERE
  LOWER(a.admission_type) = 'emergency'
  AND LOWER(a.insurance) LIKE '%medicare%'
  -- Principal diagnosis
  AND di.seq_num = 1
  -- Pneumonia (robust, case-insensitive check on long_title)
  AND LOWER(dd.long_title) LIKE '%pneumonia%'
  -- Female
  AND LOWER(p.gender) = 'f'
  -- Age at admission: anchor_age + (admission year - anchor_year)
  AND p.anchor_age IS NOT NULL
  AND p.anchor_year IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89;