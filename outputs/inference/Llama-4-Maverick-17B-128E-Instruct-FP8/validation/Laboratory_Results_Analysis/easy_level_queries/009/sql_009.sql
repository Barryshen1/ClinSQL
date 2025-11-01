WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
acs_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN female_patients ON ad.subject_id = female_patients.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON ad.hadm_id = diag.hadm_id
  WHERE diag.icd_code LIKE 'I21%' AND diag.icd_version = 10
),
troponin_measurements AS (
  SELECT acs_admissions.hadm_id, labevents.valuenum
  FROM acs_admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` labevents ON acs_admissions.hadm_id = labevents.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_labitems ON labevents.itemid = d_labitems.itemid
  WHERE d_labitems.label LIKE '%Troponin%' AND labevents.valuenum IS NOT NULL
),
nadir_troponin AS (
  SELECT hadm_id, MIN(valuenum) AS nadir_value
  FROM troponin_measurements
  GROUP BY hadm_id
)
SELECT APPROX_QUANTILES(nadir_value, 100)[OFFSET(25)] AS percentile_25th
FROM nadir_troponin;