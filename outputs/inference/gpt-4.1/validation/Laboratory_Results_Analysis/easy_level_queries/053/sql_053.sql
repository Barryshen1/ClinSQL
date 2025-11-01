WITH ischemic_stroke_admissions AS (
  -- Find admissions for the 82-year-old female patient with ischemic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 82
    AND (
      -- ICD-10 ischemic stroke
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I63') OR
        REGEXP_CONTAINS(d.icd_code, r'^I65') OR
        REGEXP_CONTAINS(d.icd_code, r'^I66')
      ))
      OR
      -- ICD-9 ischemic stroke
      (d.icd_version = 9 AND (
        REGEXP_CONTAINS(d.icd_code, r'^433') OR
        REGEXP_CONTAINS(d.icd_code, r'^434') OR
        d.icd_code = '436'
      ))
    )
),

glucose_itemids AS (
  -- Find itemids for serum/plasma glucose
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%glucose%'
    AND (
      LOWER(fluid) LIKE '%serum%' OR
      LOWER(fluid) LIKE '%plasma%'
    )
    AND LOWER(category) = 'chemistry'
),

admission_glucose AS (
  -- Get admission glucose values within 6 hours of admission
  SELECT
    ia.subject_id,
    ia.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM
    ischemic_stroke_admissions ia
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON ia.subject_id = l.subject_id AND ia.hadm_id = l.hadm_id
    JOIN glucose_itemids gi
      ON l.itemid = gi.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND (
      l.valueuom = 'mg/dL' OR l.valueuom IS NULL
    )
    AND TIMESTAMP_DIFF(l.charttime, ia.admittime, HOUR) BETWEEN 0 AND 6
)

SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER () AS admission_glucose_75th_percentile_mg_dl
FROM
  admission_glucose
;