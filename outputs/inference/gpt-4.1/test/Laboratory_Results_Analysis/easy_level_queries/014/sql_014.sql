WITH gi_bleed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age = 45
    AND p.gender = 'F'
    AND (
      LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%gi bleed%'
      OR LOWER(dd.long_title) LIKE '%gi bleeding%'
      OR LOWER(dd.long_title) LIKE '%melena%'
      OR LOWER(dd.long_title) LIKE '%hematemesis%'
      OR LOWER(dd.long_title) LIKE '%rectal bleeding%'
      OR LOWER(dd.long_title) LIKE '%upper gastrointestinal bleeding%'
      OR LOWER(dd.long_title) LIKE '%lower gastrointestinal bleeding%'
    )
),

hemoglobin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'hemoglobin'
    AND LOWER(category) = 'hematology'
),

discharge_day_hemo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN gi_bleed_admissions a
      ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
    JOIN hemoglobin_itemids h
      ON l.itemid = h.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(a.dischtime)
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS hemoglobin_75th_percentile_g_dl
FROM
  discharge_day_hemo
;