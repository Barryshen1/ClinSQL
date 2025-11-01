WITH PatientCohort AS (
  -- Select patients matching the criteria: 72-year-old female, 67-77 age range, ACS diagnosis, ICU stay
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    d.icd_code AS acs_diagnosis_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 72
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code LIKE 'I21%' -- ACS diagnosis codes (adjust as needed)
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),
ACS_Cohort_Stats AS (
  -- Calculate mean risk score and 30-day mortality for the ACS cohort
  SELECT
    AVG(risk_score) AS mean_risk_score,
    AVG(CASE WHEN deathtime <= DATE_ADD(dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS thirty_day_mortality
  FROM
    PatientCohort
),
GeneralInpatientCohort AS (
  -- Select age-matched general inpatients (no ACS, no ICU stay)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.los AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 72
    AND p.anchor_age BETWEEN;