SELECT
  STDDEV_SAMP(i.los) AS stddev_icu_los
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.icustays i
  ON a.hadm_id = i.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND (
    (d.icd_version = 9 AND d.icd_code IN ('995.91', '995.92'))
    OR
    (d.icd_version = 10 AND d.icd_code IN (
      'A41.9', 'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5',
      'A41.8', 'R65.20', 'R65.21'
    ))
  )
  AND i.los IS NOT NULL;