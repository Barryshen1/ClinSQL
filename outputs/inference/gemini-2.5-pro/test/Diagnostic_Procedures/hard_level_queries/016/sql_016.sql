WITH
  pneumonia_admissions AS (
    -- Step 1: Identify all hospital admissions with a pneumonia diagnosis.
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code
      AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%pneumonia%'
  ),

  first_icu_stays AS (
    -- Find the first ICU stay for every patient in the database.
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  patient_cohort AS (
    -- Step 2: Define the patient cohort: Male, 88-98 years, first ICU stay, with pneumonia.
    SELECT
      p.subject_id,
      a.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN first_icu_stays AS icu
      ON p.subject_id = icu.subject_id AND icu.rn = 1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON icu.hadm_id = a.hadm_id
    INNER JOIN pneumonia_admissions AS pa
      ON a.hadm_id = pa.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 88 AND 98
  ),

  procedures_counted AS (
    -- Step 3: Count procedures for each patient in the cohort within the first 72 hours of ICU admission.
    SELECT
      c.subject_id,
      c.los,
      c.hospital_expire_flag,
      COUNT(proc.icd_code) AS procedure_count
    FROM patient_cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON c.hadm_id = proc.hadm_id
      -- Filter for procedures within the first 3 days of the ICU stay.
      AND proc.chartdate >= DATE(c.intime)
      AND proc.chartdate < DATE(TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR))
    GROUP BY
      c.subject_id,
      c.los,
      c.hospital_expire_flag
  ),

  quintiled_patients AS (
    -- Step 4: Stratify patients into quintiles based on their procedure count.
    SELECT
      procedure_count,
      los,
      hospital_expire_flag,
      NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM procedures_counted
  )

-- Final Step: Aggregate metrics per quintile.
SELECT
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM quintiled_patients
GROUP BY
  quintile
ORDER BY
  quintile;