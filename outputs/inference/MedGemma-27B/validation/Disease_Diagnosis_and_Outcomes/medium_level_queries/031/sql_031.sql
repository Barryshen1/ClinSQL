WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), ICUStayInfo AS (
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    seq_num,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
), ICDCodes AS (
  SELECT
    icd_code,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
), SepsisDiagnosis AS (
  SELECT
    d.hadm_id,
    d.seq_num
  FROM
    DiagnosisInfo AS d
  JOIN
    ICDCodes AS i
  ON
    d.icd_code = i.icd_code
  WHERE
    i.long_title LIKE '%sepsis%'
    OR i.long_title LIKE '%septic shock%'
), SepsisPatient AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    AdmissionInfo AS a
  JOIN
    SepsisDiagnosis AS s
  ON
    a.hadm_id = s.hadm_id
), PatientGroup AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.deathtime,
    i.los
  FROM
    PatientInfo AS p
  JOIN
    AdmissionInfo AS a
  ON
    p.subject_id = a.subject_id
  JOIN
    ICUStayInfo AS i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    SepsisPatient AS sp
  ON
    a.hadm_id = sp.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
), Mortality AS (
  SELECT
    pg.hadm_id,
    pg.hospital_expire_flag,
    pg.deathtime,
    pg.dischtime,
    pg.los
  FROM
    PatientGroup AS pg
), MortalityAnalysis AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    deathtime,
    dischtime,
    los,
    CASE
      WHEN los <= 7
      THEN '≤7 days'
      ELSE '>7 days'
    END AS los_group
  FROM
    Mortality
), MortalitySummary AS (
  SELECT
    los_group,
    COUNT(hadm_id) AS N,
    SUM(hospital_expire_flag) AS mortality_count,
    (SUM(hospital_expire_flag) / COUNT(hadm_id)) * 100 AS mortality_percentage,
    AVG(TIMESTAMP_DIFF(deathtime, dischtime, DAY)) AS median_time_to_death
  FROM
    MortalityAnalysis
  GROUP BY
    los_group
)
SELECT
  los_group,
  N,
  mortality_percentage,
  median_time_to_death
FROM
  MortalitySummary
ORDER BY
  los_group;