WITH pneumonia_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime
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
    AND pat.anchor_age BETWEEN 45 AND 55
    AND (
      -- ICD-10 pneumonia: J12-J18
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486, only numeric codes
      OR (
        diag.icd_version = 9
        AND REGEXP_CONTAINS(diag.icd_code, r'^[0-9]+$')
        AND CAST(diag.icd_code AS INT64) BETWEEN 480 AND 486
      )
    )
),

creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),

creatinine_first24h AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
    JOIN creatinine_items ci
      ON le.itemid = ci.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= pa.admittime
    AND le.charttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pa.subject_id, pa.hadm_id
)

SELECT
  STDDEV_SAMP(avg_creatinine) AS sd_avg_serum_creatinine_first24h
FROM
  creatinine_first24h;