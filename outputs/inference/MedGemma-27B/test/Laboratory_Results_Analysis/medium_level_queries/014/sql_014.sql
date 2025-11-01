WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 79 AND 89
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1 AND d.long_title LIKE '%Acute Myocardial Infarction%'
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    l.valueuom AS troponin_unit,
    d.label AS troponin_label
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T'
), FirstTroponin AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    MIN(li.charttime) AS first_charttime
  FROM
    LabInfo AS li
  GROUP BY
    li.subject_id,
    li.hadm_id
), TroponinCategories AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    CASE
      WHEN li.troponin_value < 0.01 THEN 'Normal'
      WHEN li.troponin_value BETWEEN 0.01 AND 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    LabInfo AS li
  JOIN
    FirstTroponin AS ft ON li.subject_id = ft.subject_id AND li.hadm_id = ft.hadm_id AND li.charttime = ft.first_charttime
)
SELECT
  tc.troponin_category,
  COUNT(tc.subject_id) AS count,
  COUNT(tc.subject_id) * 100.0 / SUM(COUNT(tc.subject_id)) OVER () AS percentage
FROM
  TroponinCategories AS tc
GROUP BY
  tc.troponin_category
ORDER BY
  tc.troponin_category;