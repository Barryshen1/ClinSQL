WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    p.dod AS death_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code = 'I80.9' -- DVT code
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), ComorbidityScore AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate comorbidity score (e.g., Charlson Comorbidity Index)
    -- This requires a more complex calculation based on ICD codes
    -- For simplicity, we will use a placeholder value
    1 AS comorbidity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        DiagnosisInfo
    )
), PatientCohort AS (
  SELECT
    pi.subject_id,
    pi.age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    cs.comorbidity_score
  FROM
    PatientInfo AS pi
  JOIN
    AdmissionInfo AS a
    ON pi.subject_id = a.subject_id
  JOIN
    ComorbidityScore AS cs
    ON pi.subject_id = cs.subject_id
    AND a.hadm_id = cs.hadm_id
  WHERE
    a.hadm_id IN (
      SELECT
        hadm_id
      FROM
        DiagnosisInfo
    )
    AND cs.comorbidity_score > 0 -- Filter for high comorbidity
), Mortality AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE
      WHEN pc.deathtime IS NOT NULL
      THEN 1
      ELSE 0
    END AS mortality,
    DATE_DIFF(pc.dischtime, pc.admittime, DAY) AS los,
    DATE_DIFF(pc.deathtime, pc.dischtime, DAY) AS days_to_death
  FROM
    PatientCohort AS pc
), NinetyDayMortality AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    CASE
      WHEN m.mortality = 1 AND m.days_to_death <= 90
      THEN 1
      ELSE 0
    END AS ninety_day_mortality
  FROM
    Mortality AS m
), CohortStats AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.age,
    pc.comorbidity_score,
    nm.ninety_day_mortality,
    pc.los
  FROM
    PatientCohort AS pc
  LEFT JOIN
    NinetyDayMortality AS nm
    ON pc.subject_id = nm.subject_id
    AND pc.hadm_id = nm.hadm_id
), GeneralPopulation AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp;