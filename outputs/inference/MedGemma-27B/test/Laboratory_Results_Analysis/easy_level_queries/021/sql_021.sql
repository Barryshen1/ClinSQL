WITH MalePneumoniaAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.gender = 'M'
    AND di.long_title LIKE '%pneumonia%'
    AND a.admission_type = 'EMERGENCY' -- Assuming pneumonia admissions are typically emergency
    AND a.dischtime IS NOT NULL -- Ensure the patient was discharged
), GlucoseMeasurements AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    le.charttime,
    le.valuenum AS glucose_value,
    le.valueuom AS glucose_uom
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    li.label = 'Glucose'
    AND le.valueuom = 'mg/dL' -- Assuming standard unit for glucose
), DischargeGlucose AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.glucose_value
  FROM GlucoseMeasurements AS g
  JOIN MalePneumoniaAdmissions AS m
    ON g.subject_id = m.subject_id AND g.hadm_id = m.hadm_id
  WHERE
    g.charttime >= m.dischtime - INTERVAL '1' HOUR -- Consider glucose measurements within 1 hour before discharge
    AND g.charttime < m.dischtime -- Ensure the measurement is before discharge time
)
SELECT
  PERCENTILE_CONT(glucose_value, 0.75) AS percentile_75
FROM DischargeGlucose
WHERE
  glucose_value IS NOT NULL;