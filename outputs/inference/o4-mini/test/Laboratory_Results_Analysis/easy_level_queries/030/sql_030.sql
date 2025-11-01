WITH acs_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%unstable angina%'
),
male_acs AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    acs_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON a.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
),
troponin_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%'
),
troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
  WHERE
    le.valuenum IS NOT NULL
),
cohort_troponin AS (
  SELECT
    te.valuenum
  FROM
    troponin_events te
    JOIN male_acs m
      ON te.hadm_id = m.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON te.hadm_id = adm.hadm_id
  WHERE
    te.charttime BETWEEN adm.admittime AND adm.dischtime
)
SELECT
  MIN(valuenum) AS min_serum_troponin
FROM
  cohort_troponin;