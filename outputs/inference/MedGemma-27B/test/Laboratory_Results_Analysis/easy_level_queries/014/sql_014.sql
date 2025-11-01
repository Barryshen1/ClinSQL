WITH relevant_patients AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 45
), admission_details AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM relevant_patients)
    AND d.long_title LIKE '%GI bleeding%'
), lab_values AS (
  SELECT
    ad.subject_id,
    ad.hadm_id,
    l.charttime,
    l.valuenum AS hemoglobin,
    l.valueuom
  FROM
    admission_details AS ad
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l ON ad.subject_id = l.subject_id AND ad.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d ON l.itemid = d.itemid
  WHERE
    d.label = 'Hemoglobin'
    AND l.valueuom = 'g/dL'
    AND l.charttime >= ad.admittime
    AND l.charttime < ad.dischtime
)
SELECT
  PERCENTILE_CONT(hemoglobin, 0.75) AS percentile_75
FROM
  lab_values
WHERE
  DATE(charttime) = DATE(dischtime);