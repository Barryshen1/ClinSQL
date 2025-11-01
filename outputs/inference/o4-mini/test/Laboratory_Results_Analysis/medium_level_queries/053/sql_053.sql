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
    LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
),
troponin_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin i%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS initial_trop,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
),
filtered_first_troponin AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.initial_trop
  FROM
    first_troponin ft
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ft.hadm_id = a.hadm_id
     AND ft.charttime BETWEEN a.admittime AND a.dischtime
  WHERE
    ft.rn = 1
    AND ft.initial_trop > 0.04
),
eligible_admissions AS (
  SELECT
    fht.subject_id,
    fht.hadm_id,
    fht.initial_trop
  FROM
    filtered_first_troponin fht
    JOIN acs_admissions acs
      ON fht.hadm_id = acs.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON fht.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(initial_trop) AS mean_troponin,
  STDDEV_SAMP(initial_trop) AS sd_troponin,
  MIN(initial_trop) AS min_troponin,
  MAX(initial_trop) AS max_troponin
FROM
  eligible_admissions;