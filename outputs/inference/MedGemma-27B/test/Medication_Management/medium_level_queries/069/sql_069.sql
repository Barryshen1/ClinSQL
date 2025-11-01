WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
DiagnosisCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM PatientCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%diabetes%'
    AND di.long_title LIKE '%type 2%'
),
HeartFailureCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM DiagnosisCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%heart failure%'
),
FinalCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM HeartFailureCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
),
MedicationEvents AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    m.medication,
    m.charttime
  FROM FinalCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS m
    ON a.hadm_id = m.hadm_id
  WHERE
    m.medication LIKE '%glp-1%'
    OR m.medication LIKE '%liraglutide%'
    OR m.medication LIKE '%semaglutide%'
    OR m.medication LIKE '%dulaglutide%'
    OR m.medication LIKE '%exenatide%'
    OR m.medication LIKE '%lixisenatide%'
),
First12h AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS count_first_12h
  FROM MedicationEvents
  WHERE
    charttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR)
  GROUP BY
    subject_id,
    hadm_id
  ),
Final12h AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS count_final_12h
  FROM MedicationEvents
  WHERE
    charttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime
  GROUP BY
    subject_id,
    hadm_id
),
Combined AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    COALESCE(f12.count_first_12h, 0) AS count_first_12h,
    COALESCE(f12.count_final_12h, 0) AS count_final_12h
  FROM FinalCohort AS f
  LEFT JOIN First12h AS f12
    ON f.subject_id = f12.subject_id AND f.hadm_id = f12.hadm_id
  LEFT JOIN Final12h AS f12_final
    ON f.subject_id = f12_final.subject_;