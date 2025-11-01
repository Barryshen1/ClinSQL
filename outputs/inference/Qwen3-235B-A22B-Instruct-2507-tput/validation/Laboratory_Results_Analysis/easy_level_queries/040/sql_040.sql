WITH dka_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '250.1%')
      OR (diag.icd_version = 10 AND diag.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11'))
    )
),
admission_glucose_max AS (
  SELECT le.hadm_id, MAX(le.valuenum) AS peak_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  INNER JOIN dka_admissions da
    ON le.hadm_id = da.hadm_id
  WHERE LOWER(dlab.label) = 'glucose'
    AND LOWER(dlab.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
)
SELECT APPROX_QUANTILES(peak_glucose, 1000)[OFFSET(500)] AS median_peak_serum_glucose
FROM admission_glucose_max;