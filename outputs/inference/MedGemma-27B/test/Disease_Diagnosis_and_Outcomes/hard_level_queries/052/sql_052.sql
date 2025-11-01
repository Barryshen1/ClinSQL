WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'J44.1' -- COPD exacerbation
), PatientInfo AS (
  SELECT
    pd.subject_id,
    pd.gender,
    pd.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    PatientDiagnosis AS pd
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pd.subject_id = a.subject_id
  WHERE
    pd.gender = 'F' AND pd.anchor_age BETWEEN 75 AND 85
), Mortality AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    CASE
      WHEN pi.deathtime IS NOT NULL
      THEN 1
      ELSE 0
    END AS mortality_flag
  FROM
    PatientInfo AS pi
), LOS AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    TIMESTAMP_DIFF(pi.dischtime, pi.admittime, DAY) AS los
  FROM
    PatientInfo AS pi
), Complication AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(DISTINCT c.icd_code) AS complication_count
  FROM
    PatientInfo AS pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS c
    ON pi.subject_id = c.subject_id AND pi.hadm_id = c.hadm_id
  WHERE
    c.seq_num > 1 -- Exclude primary diagnosis
  GROUP BY
    pi.subject_id,
    pi.hadm_id
), RiskScore AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    (
      pi.anchor_age * 0.1 + -- Age
      CASE
        WHEN pi.gender = 'F'
        THEN 0.1
        ELSE 0
      END + -- Gender
      CASE
        WHEN pi.hospital_expire_flag = 1
        THEN 0.2
        ELSE 0
      END + -- Mortality
      c.complication_count * 0.05 + -- Complication
      l.los * 0.01 -- LOS
    ) AS risk_score
  FROM
    PatientInfo AS pi
  JOIN
    Complication AS c
    ON pi.subject_id = c.subject_id AND pi.hadm_id = c.hadm_id
  JOIN
    LOS AS l
    ON pi.subject_id = l.subject_id AND pi.hadm_id = l.hadm_id -- Fixed join condition
), QuartileAnalysis AS (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.risk_score,
    m.mortality_flag,
    c.complication_count,
    l.los,
    NTILE(4) OVER (ORDER BY rs.risk_score) AS risk_quartile
  FROM
    RiskScore AS rs
  JOIN
    Mortality AS m
    ON rs.subject_id = m.subject_id AND rs.hadm_id = m.hadm_id
  JOIN
    Complication AS c
    ON rs.subject_id = c.subject_id AND rs.hadm_id = c.hadm_id
  JOIN
    LOS AS l
    ON rs.subject_id = l.subject_id AND rs.hadm_id = l.hadm_id
), QuartileSummary AS (
  SELECT
    risk_quartile,
    COUNT(subject_id) AS total_patients;