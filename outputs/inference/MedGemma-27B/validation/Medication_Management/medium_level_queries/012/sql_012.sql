WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admittime >= TIMESTAMP('2000-01-01') -- Filter based on admission time, not current time.
),
DiabetesDiagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%type 2 diabetes%'
    AND d.seq_num = 1 -- Assuming the first diagnosis is the primary one
),
HeartFailureDiagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%heart failure%'
    AND d.seq_num = 1 -- Assuming the first diagnosis is the primary one
),
GLP1Medication AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%glp-1%'
    OR p.drug LIKE '%semaglutide%'
    OR p.drug LIKE '%liraglutide%'
    OR p.drug LIKE '%dulaglutide%'
    OR p.drug LIKE '%exenatide%'
),
GLP1Initiation AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.starttime
  FROM GLP1Medication AS g
  INNER JOIN PatientCohort AS pc
    ON g.subject_id = pc.subject_id AND g.hadm_id = pc.hadm_id -- Corrected join condition
),
CohortWithDiagnoses AS (
  SELECT
    pc.subject_id,
    pc.hadm_id
  FROM PatientCohort AS pc
  INNER JOIN DiabetesDiagnosis AS dd
    ON pc.subject_id = dd.subject_id AND pc.hadm_id = dd.hadm_id
  INNER JOIN HeartFailureDiagnosis AS hf
    ON pc.subject_id = hf.subject_id AND pc.hadm_id = hf.hadm_id
),
GLP1InitiationCohort AS (
  SELECT
    gic.subject_id,
    gic.hadm_id,
    gic.starttime
  FROM GLP1Initiation AS gic
  INNER JOIN CohortWithDiagnoses AS c
    ON gic.subject_id = c.subject_id AND gic.hadm_id = c.hadm_id
),
GLP1InitiationFirst12Hours AS (
  SELECT
    gic.subject_id,
    gic.hadm_id,
    gic.starttime
  FROM GLP1InitiationCohort AS gic
  WHERE
    gic.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 12 HOUR)
  FROM PatientCohort AS pc
  WHERE
    gic.subject_id = pc.subject_id AND gic.hadm_id = pc.hadm_id;