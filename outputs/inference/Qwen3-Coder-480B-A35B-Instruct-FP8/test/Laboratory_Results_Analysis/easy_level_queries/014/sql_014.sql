SELECT
  APPROX_QUANTILES(lab.valuenum, 100)[OFFSET(75)] AS hemoglobin_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON adm.hadm_id = dx.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON dx.icd_code = d_diag.icd_code AND dx.icd_version = d_diag.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` lab
  ON adm.hadm_id = lab.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
  ON lab.itemid = d_lab.itemid
WHERE
  pat.gender = 'F'
  AND pat.anchor_age = 45
  AND d_diag.icd_code IN ('578.9', 'K92.2') -- GI bleeding codes
  AND LOWER(d_lab.label) = 'hemoglobin'
  AND LOWER(d_lab.fluid) = 'blood'
  AND lab.valuenum IS NOT NULL
  AND lab.valuenum BETWEEN 0 AND 20
  AND DATE(lab.charttime) = DATE(adm.dischtime);