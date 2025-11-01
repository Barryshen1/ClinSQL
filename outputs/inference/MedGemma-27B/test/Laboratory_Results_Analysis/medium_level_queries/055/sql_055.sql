WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 81 AND 91
    AND gender = 'F'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1 -- Primary diagnosis
    AND (
      d.long_title LIKE '%chest pain%'
      OR d.long_title LIKE '%myocardial infarction%'
      OR d.long_title LIKE '%AMI%'
    )
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.value AS interpretation,
    l.valuenum AS value,
    l.valueuom AS unit
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'hs-TnT'
    AND l.charttime BETWEEN '2150-01-01' AND '2150-01-01' -- Placeholder for index value
), ICUInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ic.hadm_id = a.hadm_id
  WHERE
    a.admittime BETWEEN '2150-01-01' AND '2150-01-01' -- Placeholder for index value
)
SELECT
  li.interpretation,
  COUNT(li.subject_id) AS count,
  COUNT(li.subject_id) * 100.0 / SUM(COUNT(li.subject_id)) OVER () AS percentage,
  AVG(ic.los) AS mean_los
FROM
  PatientInfo AS pi
JOIN
  AdmissionInfo AS ai
  ON pi.subject_id = ai.subject_id
JOIN
  LabInfo AS li
  ON ai.hadm_id = li.hadm_id
JOIN
  ICUInfo AS ic
  ON ai.hadm_id = ic.hadm_id
GROUP BY
  li.interpretation
ORDER BY
  li.interpretation;