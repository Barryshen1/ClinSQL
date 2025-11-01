WITH Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.intime,
    a.outtime,
    a.los,
    p.gender,
    p.anchor_age,
    d.icd_code,
    d.icd_version,
    drg.drg_code,
    drg.drg_severity,
    drg.drg_mortality
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg ON a.hadm_id = drg.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.icd_code LIKE 'I50%' -- Heart failure codes
    AND a.stay_id IS NOT NULL
),
Cohort_Mortality AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM
    Cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON c.hadm_id = a.hadm_id
),
Cohort_Complications AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    CASE
      WHEN COUNT(DISTINCT e.seq_num) > 0 THEN 1
      ELSE 0
    END AS complication
  FROM
    Cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedureevents` AS e ON c.hadm_id = e.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los
),
Cohort_Risk AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.mortality,
    c.complication,
    drg.drg_mortality AS risk_score
  FROM
    Cohort_Mortality AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg ON c.hadm_id = drg.hadm_id -- Fixed join condition
),
FinalCohort AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    mortality,
    complication,
    risk_score
  FROM
    Cohort_Risk
  WHERE
    mortality = 0
),
CohortStats AS (
  SELECT
    MEDIAN(risk_score) AS median_risk_score,
    PERCENTILE_CONT(0.25, risk_score) AS iqr_risk_score_25,
    PERCENTILE_CONT(0.75, risk_score) AS iqr_risk_score_75,
    AVG(los) AS avg_los,
    COUNT(subject_id) AS cohort_size
  FROM
    FinalCohort
),
OverallFemaleStats AS (
  SELECT
    MEDIAN(drg.drg_mortality) AS median_risk_score,
    PERCENTILE_CONT(0.25;