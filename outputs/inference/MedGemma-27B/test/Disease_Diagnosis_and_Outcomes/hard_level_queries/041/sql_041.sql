WITH Cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%intracranial hemorrhage%'
    AND a.gender = 'M'
    AND a.anchor_age BETWEEN 68 AND 78
    AND a.dischtime > a.admittime -- Ensure it's a valid admission
    AND a.hospital_expire_flag = 0 -- Exclude patients who died in the hospital before ICU transfer
  ),
  ICU_Stays AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime
    FROM Cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  ),
  Post_ICU_Cohort AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.outtime
    FROM ICU_Stays AS icu
    WHERE
      icu.outtime > icu.intime -- Ensure valid ICU stay
  ),
  Mortality AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.anchor_age,
      p.gender,
      a.dischtime,
      a.deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.subject_id IN (
        SELECT
          subject_id
        FROM Post_ICU_Cohort
      )
  ),
  AKI AS (
    SELECT DISTINCT
      subject_id,
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code IN ('N17.9', 'N17.1', 'N17.2', 'N17.8') -- AKI ICD-10 codes
      AND subject_id IN (
        SELECT
          subject_id
        FROM Post_ICU_Cohort
      )
  ),
  ARDS AS (
    SELECT DISTINCT
      subject_id,
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` -- Corrected table name
    WHERE
      icd_code IN ('J81.0', 'J81.1', 'R09.2', 'R09.81') -- ARDS ICD-10 codes
      AND subject_id IN (
        SELECT
          subject_id
        FROM Post_ICU_Cohort
      )
  ),
  Composite_Risk_Score AS (
    SELECT
      subject_id,
      hadm_id,
      -- Calculate a composite risk score based on relevant factors (example)
      -- This is a placeholder; a real score would require specific criteria
      (
        CASE
          WHEN a.anchor_age > 70 THEN 1
          ELSE 0
        END +
        CASE
          WHEN a.gender = 'M' THEN 1
          ELSE 0
        END +
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM AKI
            WHERE AKI.subject_id = a.subject_id AND AKI.hadm_id = a.hadm;