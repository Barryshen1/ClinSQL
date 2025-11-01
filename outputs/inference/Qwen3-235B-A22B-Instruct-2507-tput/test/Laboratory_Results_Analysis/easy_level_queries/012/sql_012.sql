SELECT
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(75)] AS platelet_count_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp`.labevents l
  ON a.hadm_id = l.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_labitems dlab
  ON l.itemid = dlab.itemid
WHERE
  p.anchor_age = 87
  AND p.gender = 'F'
  AND d.icd_version = 10
  AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
  AND LOWER(dlab.label) = 'platelets'
  AND l.valuenum IS NOT NULL
  AND DATE(l.charttime) = DATE(a.dischtime);