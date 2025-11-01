WITH COPD_Patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age = 56 AND d.icd_code = '491.21'
),
Creatinine_Measurements AS (
  SELECT
    le.subject_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine'
),
First_24h_Creatinine AS (
  SELECT
    cp.subject_id,
    cm.charttime,
    cm.creatinine_value
  FROM COPD_Patients AS cp
  JOIN Creatinine_Measurements AS cm
    ON cp.subject_id = cm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON cp.subject_id = a.subject_id
  WHERE
    cm.charttime >= a.admittime AND cm.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
)
SELECT
  PERCENTILE_CONT(0.75, creatinine_value)
FROM First_24h_Creatinine;