WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 59
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),
LabEvents AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value,
    dli.label AS troponin_t_label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
    AND le.valuenum > 0.01
),
FirstTroponin AS (
  SELECT
    hadm_id,
    MIN(charttime) AS first_troponin_time
  FROM
    LabEvents
  GROUP BY
    hadm_id
)
SELECT
  COUNT(DISTINCT a.hadm_id) AS n,
  AVG(a.anchor_age) AS mean_age,
  STDDEV(a.anchor_age) AS sd_age,
  MIN(a.anchor_age) AS min_age,
  MAX(a.anchor_age) AS max_age,
  PERCENTILE_CONT(a.anchor_age, 0.5) AS median_age,
  PERCENTILE_CONT(a.anchor_age, 0.25) AS p25_age,
  PERCENTILE_CONT(a.anchor_age, 0.75) AS p75_age
FROM
  Admissions AS a
INNER JOIN
  FirstTroponin AS ft
  ON a.hadm_id = ft.hadm_id
WHERE
  a.subject_id = 59;