WITH dka_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (di.icd_version = 10 AND (
            di.icd_code LIKE 'E10.1%' OR
            di.icd_code LIKE 'E11.1%' OR
            di.icd_code LIKE 'E13.1%' OR
            di.icd_code LIKE 'E14.1%'
         ))
     OR (di.icd_version = 9 AND (
            di.icd_code LIKE '250.1%'  -- covers 250.10, 250.11, 250.12, 250.13
         ))
),
female_58 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age = 58
),
serum_glucose AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(dl.label) LIKE '%glucose%'
    AND LOWER(dl.fluid) = 'serum'
),
peak_per_admission AS (
  SELECT sg.hadm_id,
         MAX(sg.valuenum) AS peak_glucose
  FROM serum_glucose sg
  JOIN dka_admissions da
    ON sg.subject_id = da.subject_id
   AND sg.hadm_id = da.hadm_id
  JOIN female_58 f
    ON sg.subject_id = f.subject_id
  GROUP BY sg.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_glucose, 2)[OFFSET(1)] AS median_peak_glucose
FROM peak_per_admission;