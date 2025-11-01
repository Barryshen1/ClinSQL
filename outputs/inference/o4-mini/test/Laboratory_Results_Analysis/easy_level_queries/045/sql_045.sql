WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
    AND p.gender = 'M'
    AND p.anchor_age = 83
),
creatinine_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinine%'
),
index_creatinine AS (
  -- Find the earliest creatinine per admission within 24h
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.valuenum AS creatinine_value
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum,
      ROW_NUMBER() OVER (
        PARTITION BY le.subject_id, le.hadm_id
        ORDER BY le.charttime
      ) AS rn
    FROM
      sepsis_admissions AS se
      JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON se.subject_id = le.subject_id
       AND se.hadm_id = le.hadm_id
      JOIN creatinine_items AS ci
        ON le.itemid = ci.itemid
    WHERE
      le.valuenum IS NOT NULL
      AND le.charttime BETWEEN se.admittime
                          AND TIMESTAMP_ADD(se.admittime, INTERVAL 1 DAY)
  ) AS ce
  WHERE
    ce.rn = 1
)
SELECT
  MAX(creatinine_value) AS max_index_serum_creatinine
FROM
  index_creatinine;