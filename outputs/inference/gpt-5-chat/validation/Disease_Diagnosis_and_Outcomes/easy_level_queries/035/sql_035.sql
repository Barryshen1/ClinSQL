WITH upper_gi_bleed_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
    AND adm.subject_id = dx.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age = 70
    AND dx.seq_num = 1
    -- filter diagnosis description for upper GI bleeding keywords
    AND (
      LOWER(ddx.long_title) LIKE '%upper gastrointestinal%'
      OR LOWER(ddx.long_title) LIKE '%upper gi%'
      OR LOWER(ddx.long_title) LIKE '%hematemesis%'
      OR LOWER(ddx.long_title) LIKE '%melena%'
      OR LOWER(ddx.long_title) LIKE '%peptic ulcer%' AND LOWER(ddx.long_title) LIKE '%hemorrhage%'
      OR LOWER(ddx.long_title) LIKE '%gi hemorrhage%'
      OR LOWER(ddx.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(ddx.long_title) LIKE '%bleed%'
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS p75_los_days
FROM
  upper_gi_bleed_admissions;