WITH StrokeAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I63%' -- Ischemic stroke codes
    AND p.gender = 'M'
    AND p.anchor_age = 50
),
HemoglobinMeasurements AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hemoglobin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  WHERE
    l.itemid = 50912 -- Hemoglobin lab item ID
)
SELECT
  MIN(h.hemoglobin_value) AS min_hemoglobin
FROM StrokeAdmissions AS s
JOIN HemoglobinMeasurements AS h
  ON s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id
WHERE
  h.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR);