WITH DischargeDay AS (
  SELECT
    hadm_id,
    dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hospital_expire_flag = 0
),
SepsisPatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    a.gender = 'M'
    AND d.icd_code LIKE 'A41%' -- Sepsis ICD-10 code
),
LactateMeasurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS lactate_value
  FROM
    `physionet-data.mimiciv_3_1_icu.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
  ON
    l.itemid = dli.itemid
  WHERE
    dli.label = 'Lactate'
)
SELECT
  PERCENTILE_CONT(0.25, lactate_value) AS iqr_25,
  PERCENTILE_CONT(0.75, lactate_value) AS iqr_75
FROM
  LactateMeasurements AS lm
JOIN
  DischargeDay AS dd
ON
  lm.hadm_id = dd.hadm_id
JOIN
  SepsisPatients AS sp
ON
  lm.subject_id = sp.subject_id
  AND lm.hadm_id = sp.hadm_id
WHERE
  lm.charttime >= dd.dischtime - INTERVAL '1' DAY
  AND lm.charttime < dd.dischtime + INTERVAL '1' DAY;