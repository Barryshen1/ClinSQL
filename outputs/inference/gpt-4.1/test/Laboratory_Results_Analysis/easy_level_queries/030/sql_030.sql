WITH acs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
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
    AND pat.anchor_age = 57
    AND (
      -- ICD-10 ACS codes
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'I21%' OR
        diag.icd_code LIKE 'I22%' OR
        diag.icd_code = 'I20.0'
      ))
      -- ICD-9 ACS codes
      OR (diag.icd_version = 9 AND (
        diag.icd_code LIKE '410%' OR
        diag.icd_code = '4111'
      ))
    )
)

, troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%'
    AND LOWER(fluid) = 'blood'
)

SELECT
  acs.subject_id,
  acs.hadm_id,
  acs.admittime,
  acs.dischtime,
  MIN(lab.valuenum) AS min_troponin
FROM
  acs_admissions acs
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON acs.subject_id = lab.subject_id
    AND acs.hadm_id = lab.hadm_id
  JOIN troponin_items ti
    ON lab.itemid = ti.itemid
WHERE
  lab.valuenum IS NOT NULL
  AND lab.charttime BETWEEN acs.admittime AND acs.dischtime
GROUP BY
  acs.subject_id, acs.hadm_id, acs.admittime, acs.dischtime
ORDER BY
  min_troponin ASC;