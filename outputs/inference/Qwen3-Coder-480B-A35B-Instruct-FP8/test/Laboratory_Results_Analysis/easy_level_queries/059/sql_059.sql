SELECT
  APPROX_QUANTILES(lab.valuenum, 100)[OFFSET(75)] AS platelet_75th_percentile
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_dx
  ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents AS lab
  ON adm.hadm_id = lab.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems AS d_lab
  ON lab.itemid = d_lab.itemid
WHERE
  pat.gender = 'M'
  AND pat.anchor_age = 93
  AND d_dx.long_title LIKE '%sepsis%'
  AND d_lab.label = 'platelet'
  AND d_lab.fluid = 'blood'
  AND lab.valuenum IS NOT NULL
  AND DATE(lab.charttime) = DATE(adm.dischtime);