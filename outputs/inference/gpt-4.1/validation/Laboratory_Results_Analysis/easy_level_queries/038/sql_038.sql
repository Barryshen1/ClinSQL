WITH ischemic_stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    pat.anchor_age,
    pat.anchor_year,
    pat.gender
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
      -- ICD-10: I63.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
      -- ICD-9: 433.x or 434.x
      OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%'))
    )
)
, age_50_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM
    ischemic_stroke_admissions
  WHERE
    -- Calculate age at admission
    (anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)) = 50
)
, hemoglobin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'hemoglobin'
)
, min_hemo_per_admission AS (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS min_hemoglobin
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN age_50_admissions adm
      ON le.hadm_id = adm.hadm_id
    JOIN hemoglobin_itemids hi
      ON le.itemid = hi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= adm.admittime
    AND le.charttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR)
  GROUP BY
    le.hadm_id
)
SELECT
  MIN(min_hemoglobin) AS min_hemoglobin_24h
FROM
  min_hemo_per_admission;