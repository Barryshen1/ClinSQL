WITH SepsisPatients AS (
  -- Identify patients with sepsis based on ICD-9 codes
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS icd
    ON p.subject_id = icd.subject_id
  WHERE
    icd.icd_code IN ('001', '001.0', '001.1', '001.2', '001.3', '001.4', '001.5', '001.6', '001.7', '001.8', '001.9') -- Sepsis ICD-9 codes
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
), FirstICUStay AS (
  -- Identify the first ICU stay for each patient
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.stay_id IN (
      SELECT
        MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = s.subject_id
      GROUP BY
        subject_id
    )
), SepsisICUStay AS (
  -- Combine sepsis patients with their first ICU stay
  SELECT
    sp.subject_id,
    fis.stay_id,
    fis.intime
  FROM SepsisPatients AS sp
  JOIN FirstICUStay AS fis
    ON sp.subject_id = fis.subject_id
), ProceduresInFirst48Hours AS (
  -- Count distinct procedures within the first 48 hours of the ICU stay
  SELECT
    sis.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM SepsisICUStay AS sis
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON sis.subject_id = pe.subject_id AND sis.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN sis.intime AND TIMESTAMP_ADD(sis.intime, INTERVAL 48 HOUR)
  GROUP BY
    sis.subject_id
), NinetyPercentileProcedures AS (
  -- Calculate the 90th percentile of distinct procedures
  SELECT
    PERCENTILE_CONT(0.90, distinct_procedures) AS p90_procedures
  FROM ProceduresInFirst48Hours
), HospitalLOS AS (
  -- Calculate hospital LOS for sepsis ICU patients
  SELECT
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN SepsisICUStay AS sis
    ON a.subject_id = sis.subject_id AND a.hadm_id = sis.hadm_id -- Corrected join condition
  WHERE
    a.dischtime IS NOT NULL
), InHospitalMortality AS (
  -- Calculate in-hospital mortality for sepsis ICU patients
  SELECT
    a.subject_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN SepsisICUStay AS sis
    ON a.subject_id = sis.subject_id AND a.hadm_id = sis.hadm_id -- Corrected join condition
), AgeMatchedControls AS (
  -- Identify age-matched controls (female patients aged 66-76 without sepsis)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND;