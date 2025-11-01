WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 55-65, asthma exacerbation diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.icd_code -- Include ICD code for diagnosis confirmation
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.icd_code_version = 10 -- Assuming ICD-10 for asthma exacerbation
    AND a.icd_code IN ('J45.901', 'J45.909') -- Example ICD-10 codes for asthma exacerbation
),

LabInstabilityScore AS (
  -- Calculate the lab instability score for each patient within the first 48 hours
  SELECT
    p.subject_id,
    p.hadm_id,
    SUM(CASE
      WHEN ABS(le.value - le.prev_value) > 0.5 THEN 1
      ELSE 0
    END) AS instability_score
  FROM
    PatientCohort AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON p.subject_id = le.subject_id AND p.hadm_id = le.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS prev_le
    ON p.subject_id = prev_le.subject_id
    AND p.hadm_id = prev_le.hadm_id
    AND le.itemid = prev_le.itemid
    AND prev_le.charttime < le.charttime
  WHERE
    le.charttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR)
  GROUP BY
    p.subject_id,
    p.hadm_id
),

TopTierPatients AS (
  -- Select patients with instability score in the top 5% (95th percentile)
  SELECT
    subject_id,
    hadm_id,
    instability_score
  FROM
    LabInstabilityScore
  WHERE
    instability_score >= (SELECT PERCENTILE_CONT(instability_score, 0.95) FROM LabInstabilityScore)
),

PatientStats AS (
  -- Calculate LOS and mortality for the top tier patients
  SELECT
    tt.subject_id,
    tt.hadm_id,
    tt.instability_score,
    a.los,
    a.hospital_expire_flag
  FROM
    TopTierPatients AS tt
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON tt.subject_id = a.subject_id AND tt.hadm_id = a.hadm_id -- Corrected join condition
)
-- Final selection and aggregation
SELECT
  AVG(los) AS avg_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  PERCENTILE_CONT(instability_score, 0.95) AS avg_critical_lab_rate
FROM
  PatientStats;