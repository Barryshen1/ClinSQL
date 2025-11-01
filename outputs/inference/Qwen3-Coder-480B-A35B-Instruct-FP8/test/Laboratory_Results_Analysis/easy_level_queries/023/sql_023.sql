SELECT
  APPROX_QUANTILES(l.valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(l.valuenum, 4)[OFFSET(3)] AS q3
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
  ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON a.hadm_id = l.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON l.itemid = dl.itemid
WHERE
  p.gender = 'M'
  AND LOWER(did.long_title) LIKE '%sepsis%'
  AND LOWER(dl.label) LIKE '%lactate%'
  AND l.valuenum IS NOT NULL
  AND DATE(l.charttime) = DATE(a.dischtime);