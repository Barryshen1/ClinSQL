WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
),
AdmissionCohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientCohort AS pc
    ON a.subject_id = pc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('I50', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9') -- Acute HF codes
),
GLP1Medications AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS p
  WHERE
    p.medication LIKE '%glp-1%'
    OR p.medication LIKE '%semaglutide%'
    OR p.medication LIKE '%liraglutide%'
    OR p.medication LIKE '%dulaglutide%'
    OR p.medication LIKE '%exenatide%'
    OR p.medication LIKE '%lixisenatide%'
),
GLP1Initiation AS (
  SELECT
    ac.hadm_id,
    MIN(glp1.charttime) AS initiation_time -- Use MIN to get the earliest initiation time if multiple entries exist
  FROM AdmissionCohort AS ac
  JOIN GLP1Medications AS glp1
    ON ac.hadm_id = glp1.hadm_id
  WHERE
    glp1.charttime BETWEEN ac.admittime AND ac.dischtime
  GROUP BY ac.hadm_id -- Group by hadm_id to get one initiation time per admission
)
SELECT
  COUNT(DISTINCT ac.hadm_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN glp1.initiation_time BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN ac.hadm_id END) AS first_72h_initiation,
  COUNT(DISTINCT CASE WHEN glp1.initiation_time BETWEEN TIMESTAMP_SUB(ac.dischtime, INTERVAL 24 HOUR) AND ac.dischtime THEN ac.hadm_id END) AS final_24h_initiation,
  (COUNT(DISTINCT CASE WHEN glp1.initiation_time BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR) THEN ac.hadm_id END) / COUNT(DISTINCT ac.hadm_id;