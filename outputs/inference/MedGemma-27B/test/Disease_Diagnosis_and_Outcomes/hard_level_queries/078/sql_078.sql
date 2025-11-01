WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
),
HeartFailureCohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.deathtime,
    pc.dischtime,
    pc.hospital_expire_flag,
    pc.admittime
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.subject_id = d.subject_id AND pc.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I50%' -- Heart failure codes
),
MortalityAKIARDS AS (
  SELECT
    hfc.subject_id,
    hfc.hadm_id,
    hfc.deathtime,
    hfc.dischtime,
    hfc.hospital_expire_flag,
    CASE
      WHEN hfc.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
          ON le.itemid = li.itemid
        WHERE
          le.subject_id = hfc.subject_id
          AND le.hadm_id = hfc.hadm_id
          AND li.label = 'Creatinine'
          AND le.valuenum > 1.5
      ) THEN 1
      ELSE 0
    END AS aki,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        WHERE
          d.subject_id = hfc.subject_id
          AND d.hadm_id = hfc.hadm_id
          AND d.icd_code LIKE 'J80%' -- ARDS codes
      ) THEN 1
      ELSE 0
    END AS ards
  FROM HeartFailureCohort AS hfc
),
Survival AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(dischtime, admit_time, DAY)
      ELSE NULL
    END AS survival_days
  FROM MortalityAKIARDS
),
CompositeRiskScore AS (
  SELECT
    subject_id,
    hadm_id,
    mortality,
    aki,
    ards,
    CASE
      WHEN mortality = 1 OR aki = 1 OR ards = 1 THEN 1
      ELSE 0
    END AS composite_risk
  FROM MortalityAKIARDS
),
RiskScoreDistribution AS (
  SELECT
    PERCENTILE_CONT(composite_risk, 0.0) AS min_risk,
    PERCENTILE_CONT(composite_risk, 0.25) AS p25_risk,
    PERCENTILE_CONT(composite_risk, 0.5) AS median_risk,
    PERCENTILE_CONT(composite_risk, 0.75) AS p75_risk,
    PERCENTILE_CONT(composite_risk, 0.9) AS p90_risk,
    MAX(composite_risk) AS max_risk
  FROM CompositeRiskScore
)
SELECT
  SUM(;