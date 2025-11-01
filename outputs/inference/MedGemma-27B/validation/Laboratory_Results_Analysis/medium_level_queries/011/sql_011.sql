WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1
), LabInfo AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
), LabItemInfo AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
)
SELECT
  CASE
    WHEN li.valuenum < 14
    THEN 'normal'
    WHEN li.valuenum BETWEEN 14 AND 99
    THEN 'borderline'
    ELSE 'myocardial injury'
  END AS tnt_category,
  COUNT(*) AS patient_count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage
FROM
  PatientInfo AS pi
JOIN
  AdmissionInfo AS ai ON pi.subject_id = ai.subject_id
JOIN
  DiagnosisInfo AS di ON ai.hadm_id = di.hadm_id
JOIN
  LabInfo AS li ON ai.hadm_id = li.hadm_id
JOIN
  LabItemInfo AS lii ON li.itemid = lii.itemid
WHERE
  pi.gender = 'M' AND pi.anchor_age BETWEEN 61 AND 71 AND di.icd_code = 'I20.9' AND lii.label = 'hs-TnT' AND li.charttime = (
    SELECT
      MIN(charttime)
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS li2
    WHERE
      li2.subject_id = li.subject_id AND li2.hadm_id = li.hadm_id AND li2.itemid = li.itemid
  )
GROUP BY
  tnt_category
ORDER BY
  CASE
    WHEN tnt_category = 'normal'
    THEN 1
    WHEN tnt_category = 'borderline'
    THEN 2
    ELSE 3
  END;