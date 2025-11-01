WITH
  -- Step 1: Identify the cohort of male ICU patients, aged 82-92, with cardiogenic shock.
  cohort AS (
    SELECT DISTINCT
      icu.stay_id,
      icu.hadm_id,
      icu.intime,
      adm.hospital_expire_flag,
      -- Calculate hospital LOS in days for precision
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 82 AND 92
      AND dx.icd_code IN ('785.51', 'R57.0') -- Cardiogenic Shock for ICD-9 and ICD-10
  ),
  -- Step 2: Count procedures within the first 24 hours for each stay in the cohort.
  procedures_first_24h AS (
    SELECT
      cohort.stay_id,
      COUNT(pe.itemid) AS procedure_count
    FROM
      cohort
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON cohort.stay_id = pe.stay_id
    WHERE
      pe.starttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 24 HOUR)
    GROUP BY
      cohort.stay_id
  ),
  -- Step 3: Combine cohort data with procedure counts and assign quintiles.
  stay_quintiles AS (
    SELECT
      cohort.hospital_los_days,
      cohort.hospital_expire_flag,
      COALESCE(p24.procedure_count, 0) AS procedure_count,
      -- Stratify into 5 groups (quintiles) based on the procedure count
      NTILE(5) OVER (
        ORDER BY
          COALESCE(p24.procedure_count, 0)
      ) AS quintile
    FROM
      cohort
    LEFT JOIN
      procedures_first_24h AS p24
      ON cohort.stay_id = p24.stay_id
  )
-- Step 4: Aggregate metrics for each quintile.
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percentage
FROM
  stay_quintiles
GROUP BY
  quintile
ORDER BY
  quintile;