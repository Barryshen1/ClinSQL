WITH first_icu_stay AS (
  -- Identify the first ICU stay for each patient in the database
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
hepatic_failure_admissions AS (
  -- Identify hospital admissions with a diagnosis of hepatic failure
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    LOWER(ddx.long_title) LIKE '%hepatic failure%'
),
patient_cohort AS (
  -- Build the primary cohort of male patients, 90-100, on their first ICU stay with hepatic failure
  SELECT
    p.subject_id,
    adm.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    first_icu_stay AS icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN
    hepatic_failure_admissions AS hfa
    ON adm.hadm_id = hfa.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND icu.rn = 1 -- Filter for the patient's first-ever ICU stay
),
procedures_count AS (
  -- Count distinct procedures for each patient in the cohort within the first 72 hours
  SELECT
    pc.subject_id,
    pc.los,
    pc.hospital_expire_flag,
    COUNT(DISTINCT proc.icd_code) AS num_procedures
  FROM
    patient_cohort AS pc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON pc.hadm_id = proc.hadm_id
    -- Filter for procedures within approx. first 72 hours of ICU admission.
    -- This uses the ICU admission day and the next two full days as a proxy.
    AND proc.chartdate >= DATE(pc.intime)
    AND proc.chartdate <= DATE_ADD(DATE(pc.intime), INTERVAL 2 DAY)
  GROUP BY
    pc.subject_id,
    pc.los,
    pc.hospital_expire_flag
),
patient_quartiles AS (
  -- Stratify patients into quartiles based on their procedure count
  SELECT
    subject_id,
    los,
    hospital_expire_flag,
    num_procedures,
    NTILE(4) OVER (ORDER BY num_procedures) AS quartile
  FROM
    procedures_count
)
-- Aggregate results by quartile to report final metrics
SELECT
  quartile,
  COUNT(DISTINCT subject_id) AS number_of_patients,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures,
  ROUND(AVG(num_procedures), 2) AS mean_procedures,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_pct
FROM
  patient_quartiles
GROUP BY
  quartile
ORDER BY
  quartile;