WITH dka_admissions AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE (
    -- ICD-9: 250.1x
    (diag.icd_version = 9 AND diag.icd_code LIKE '250.1%') OR
    -- ICD-10: E10.1, E11.1
    (diag.icd_version = 10 AND diag.icd_code IN ('E101', 'E111'))
  )
),
female_dka AS (
  SELECT da.subject_id, da.hadm_id
  FROM dka_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON da.subject_id = p.subject_id
  WHERE p.gender = 'F'
  -- Removed age filter to answer the broader question about female DKA admissions
),
peak_glucose AS (
  SELECT fd.hadm_id, MAX(l.valuenum) AS peak_glucose
  FROM female_dka fd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON fd.hadm_id = l.hadm_id AND fd.subject_id = l.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON l.itemid = dli.itemid
  WHERE dli.itemid = 50809  -- Glucose (serum)
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0  -- exclude negative values
  GROUP BY fd.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_glucose, 100)[OFFSET(50)] AS median_peak_glucose
FROM peak_glucose;