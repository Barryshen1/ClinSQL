WITH pneumonia_admissions AS (
  -- Find all male admissions with pneumonia
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    -- Pneumonia ICD-10: J12-J18, ICD-9: 480-486
    AND (
      (diag.icd_version = 9 AND SAFE_CAST(diag.icd_code AS INT64) BETWEEN 480 AND 486)
      OR
      (diag.icd_version = 10 AND diag.icd_code BETWEEN 'J12' AND 'J18')
    )
    -- For the specific patient, you could add: AND pat.anchor_age = 61
),

creatinine_itemids AS (
  -- Find itemids for serum creatinine
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),

nadir_creatinine AS (
  -- For each male pneumonia admission, get the nadir (lowest) serum creatinine
  SELECT
    pa.subject_id,
    pa.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
    JOIN creatinine_itemids ci
      ON le.itemid = ci.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY
    pa.subject_id, pa.hadm_id
)

SELECT
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] AS percentile_75,
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] - APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS IQR
FROM
  nadir_creatinine
;