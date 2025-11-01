SELECT
  STDDEV(icu.los) AS los_sd
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON a.hadm_id = dx.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON a.hadm_id = icu.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 51 AND 61
  AND dx.seq_num = 1
  AND LOWER(d.long_title) LIKE '%hemorrhagic stroke%'
  AND icu.los IS NOT NULL;