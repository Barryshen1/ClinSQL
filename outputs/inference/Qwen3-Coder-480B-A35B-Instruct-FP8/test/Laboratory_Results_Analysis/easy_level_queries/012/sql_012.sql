SELECT
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(75)] AS platelet_75th_percentile
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents l
  ON a.hadm_id = l.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems dl
  ON l.itemid = dl.itemid
WHERE
  p.anchor_age = 87
  AND p.gender = 'F'
  AND did.icd_code LIKE 'I61%'
  AND did.icd_version = 10
  AND dl.label = 'Platelets'
  AND l.valuenum IS NOT NULL
  AND DATE(l.charttime) = DATE(a.dischtime);