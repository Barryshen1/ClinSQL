WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 66
    AND LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime
),
creat_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%creatinine%'
    AND LOWER(category) LIKE '%chemistry%'
    AND LOWER(fluid) LIKE '%blood%'
),
creat24h AS (
  SELECT
    ha.hadm_id,
    MAX(le.valuenum) AS max_creat
  FROM
    hf_admissions AS ha
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON ha.subject_id = le.subject_id
      AND ha.hadm_id    = le.hadm_id
    JOIN creat_items AS ci
      ON le.itemid = ci.itemid
  WHERE
    le.charttime BETWEEN ha.admittime
      AND TIMESTAMP_ADD(ha.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY
    ha.hadm_id
)
SELECT
  MAX(max_creat) AS overall_max_creatinine_first24h
FROM
  creat24h;