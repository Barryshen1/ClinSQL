WITH PatientDKA AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_code = 'E11.10'
), PatientAllMale AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
), Mortality AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL
      THEN 1
      ELSE 0
    END AS mortality_flag,
    CASE
      WHEN deathtime IS NOT NULL
      THEN DATE_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
), LOS AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
), Complications AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS complication_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE 'I%' -- Cardiovascular
    OR icd_code LIKE 'G%' -- Neurologic
  GROUP BY
    hadm_id
), RiskScore AS (
  SELECT
    hadm_id,
    -- Calculate risk score based on age, gender, and comorbidities
    -- This is a placeholder, replace with actual risk score calculation
    (
      CASE
        WHEN anchor_age BETWEEN 39 AND 49
        THEN 10
        ELSE 5
      END
    ) + (
      CASE
        WHEN gender = 'M'
        THEN 5
        ELSE 0
      END
    ) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
)
SELECT
  'DKA' AS patient_group,
  AVG(m.mortality_flag) AS mean_mortality,
  AVG(rs.risk_score) AS mean_risk_score,
  AVG(l.los) AS mean_los,
  AVG(c.complication_count) AS mean_complication_count
FROM PatientDKA AS pd
INNER JOIN Mortality AS m
  ON pd.hadm_id = m.hadm_id
INNER JOIN LOS AS l
  ON pd.hadm_id = l.hadm_id
INNER JOIN Complications AS c
  ON pd.hadm_id = c.hadm_id
INNER JOIN RiskScore AS rs
  ON pd.hadm_id;