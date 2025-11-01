WITH pneumonia_admissions AS (
  -- female hospital admissions with any diagnosis labeled as pneumonia
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
      ON dx.icd_code = dxd.icd_code
      AND dx.icd_version = dxd.icd_version
  WHERE
    LOWER(p.gender) = 'f'
    AND LOWER(dxd.long_title) LIKE '%pneumonia%'
),

creatinine_items AS (
  -- lab itemids that look like creatinine (prefer serum/blood where available)
  SELECT
    itemid,
    label,
    fluid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinine%'
    AND (
      LOWER(fluid) LIKE '%serum%'
      OR LOWER(fluid) LIKE '%blood%'
      OR fluid IS NULL
    )
),

admission_creatinine_first24 AS (
  -- per admission average creatinine within the first 24 hours after admittime
  SELECT
    pa.subject_id,
    pa.hadm_id,
    AVG(le.valuenum) AS avg_creatinine_24h,
    COUNT(*) AS n_measurements_24h
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.hadm_id = le.hadm_id
    JOIN creatinine_items ci
      ON le.itemid = ci.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= pa.admittime
    AND le.charttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pa.subject_id,
    pa.hadm_id
  HAVING
    COUNT(*) >= 1
)

SELECT
  ac.hadm_id,
  ac.subject_id,
  ac.avg_creatinine_24h AS min_24h_avg_creatinine
FROM
  admission_creatinine_first24 ac
WHERE
  ac.avg_creatinine_24h = (
    SELECT MIN(avg_creatinine_24h) FROM admission_creatinine_first24
  )
LIMIT 1;