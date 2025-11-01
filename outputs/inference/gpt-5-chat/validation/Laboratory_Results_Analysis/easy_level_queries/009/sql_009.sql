WITH female_acs AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (
      -- ICD-9 ACS codes
      (di.icd_version = 9 AND (
           di.icd_code LIKE '410%' -- AMI
        OR di.icd_code LIKE '4111%' -- intermediate coronary syndrome
        OR di.icd_code LIKE '4110%' -- unstable angina
        OR di.icd_code LIKE '4118%' -- other acute/subacute ischemic heart disease
      ))
      -- ICD-10 ACS codes
      OR (di.icd_version = 10 AND (
           di.icd_code LIKE 'I21%' -- AMI
        OR di.icd_code LIKE 'I22%' -- subsequent MI
        OR di.icd_code = 'I200'    -- unstable angina
      ))
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
nadir_per_adm AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    MIN(le.valuenum) AS nadir_troponin
  FROM female_acs fa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.subject_id = le.subject_id
    AND fa.hadm_id = le.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
  GROUP BY fa.subject_id, fa.hadm_id
)
SELECT
  PERCENTILE_CONT(nadir_troponin, 0.25) OVER() AS pct25_nadir_troponin
FROM nadir_per_adm
LIMIT 1;