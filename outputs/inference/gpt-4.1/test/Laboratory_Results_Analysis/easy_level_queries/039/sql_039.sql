WITH pneumonia_admissions AS (
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
    AND (
      -- ICD-10 pneumonia: J12-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^48[0-6]'))
      -- Also allow diagnosis description for edge cases
      OR LOWER(dicd.long_title) LIKE '%pneumonia%'
    )
)

, creatinine_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'blood'
)

, peak_creatinine_per_admission AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    MAX(le.valuenum) AS peak_creatinine
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
    JOIN creatinine_items ci
      ON le.itemid = ci.itemid
  WHERE
    le.valuenum IS NOT NULL
  GROUP BY
    pa.subject_id,
    pa.hadm_id
)

SELECT
  STDDEV_SAMP(peak_creatinine) AS stddev_peak_serum_creatinine
FROM
  peak_creatinine_per_admission
;