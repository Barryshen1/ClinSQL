SELECT
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON a.hadm_id = l.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON l.itemid = dl.itemid
WHERE
  p.anchor_age = 82
  AND p.gender = 'F'
  AND LOWER(d.long_title) LIKE '%ischemic stroke%'
  AND LOWER(dl.label) LIKE '%glucose%'
  AND dl.fluid = 'Blood'
  AND l.valuenum IS NOT NULL
  AND l.valueuom = 'mg/dL'
  AND l.charttime >= a.admittime;