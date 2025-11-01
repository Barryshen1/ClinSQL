WITH sepsis_admissions AS (
  -- Find admissions for 76-year-old females with sepsis
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
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age = 76
    AND (
      -- ICD-10 sepsis codes
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'A40%' OR
        diag.icd_code LIKE 'A41%'
      ))
      -- ICD-9 sepsis codes
      OR (diag.icd_version = 9 AND (
        diag.icd_code LIKE '99591' OR
        diag.icd_code LIKE '99592' OR
        diag.icd_code LIKE '78552' OR
        diag.icd_code LIKE '038%' OR
        diag.icd_code LIKE '99932' OR
        diag.icd_code LIKE '7907'
      ))
    )
),
platelet_itemids AS (
  -- Find itemids for platelet count
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
    AND LOWER(label) LIKE '%count%'
),
platelet_24h AS (
  -- For each qualifying admission, get platelet counts in first 24h
  SELECT
    sa.subject_id,
    sa.hadm_id,
    AVG(le.valuenum) AS avg_platelet_24h
  FROM
    sepsis_admissions sa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON sa.subject_id = le.subject_id
      AND sa.hadm_id = le.hadm_id
    JOIN platelet_itemids pi
      ON le.itemid = pi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= sa.admittime
    AND le.charttime < TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    sa.subject_id,
    sa.hadm_id
)
SELECT
  APPROX_QUANTILES(avg_platelet_24h, 2)[OFFSET(1)] AS median_platelet_count_24h
FROM
  platelet_24h
;