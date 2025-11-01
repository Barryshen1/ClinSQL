WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND d.icd_code IN ('I50', 'I11', 'I13', 'I10') -- Heart Failure codes
),
MedicationUse AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.charttime,
    m.medication,
    m.route
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS m
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON m.subject_id = p.subject_id
  WHERE
    m.medication LIKE '%glp-1%'
    AND m.route IN ('SUBQ', 'SQ') -- Subcutaneous route for GLP-1 agonists
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
SELECT
  COUNT(DISTINCT CASE WHEN mu.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 48 HOUR) THEN mu.subject_id END) / COUNT(DISTINCT pc.subject_id) * 100 AS first_48_hours_prevalence,
  COUNT(DISTINCT CASE WHEN mu.charttime BETWEEN TIMESTAMP_SUB(ai.dischtime, INTERVAL 24 HOUR) AND ai.dischtime THEN mu.subject_id END) / COUNT(DISTINCT pc.subject_id) * 100 AS final_24_hours_prevalence,
  COUNT(DISTINCT CASE WHEN mu.charttime BETWEEN TIMESTAMP_SUB(ai.dischtime, INTERVAL 24 HOUR) AND ai.dischtime THEN mu.subject_id END) - COUNT(DISTINCT CASE WHEN mu.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 48 HOUR) THEN mu.subject_id END) AS net_change
FROM PatientCohort AS pc
INNER JOIN AdmissionInfo AS ai
  ON pc.subject_id = ai.subject_id
INNER JOIN MedicationUse AS mu
  ON pc.subject_id = mu.subject_id
  AND ai.hadm_id = mu.hadm_id
WHERE
  ai.dischtime IS NOT NULL
GROUP BY
  pc.subject_id;