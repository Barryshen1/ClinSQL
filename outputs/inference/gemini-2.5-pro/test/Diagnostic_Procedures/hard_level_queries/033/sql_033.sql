WITH
  -- Step 1: Find all hospital admissions with a pneumonia diagnosis
  pneumonia_adms AS (
    SELECT DISTINCT
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code
      AND dx.icd_version = ddx.icd_version
    WHERE
      LOWER(ddx.long_title) LIKE '%pneumonia%'
  ),
  -- Step 2: Identify the first ICU stay for male patients aged 37-47 with pneumonia
  cohort AS (
    SELECT
      icu.stay_id,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag
    FROM (
      SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    INNER JOIN
      pneumonia_adms
      ON icu.hadm_id = pneumonia_adms.hadm_id
    WHERE
      icu.stay_rank = 1
      AND pat.gender = 'M'
      AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 37 AND 47
  ),
  -- Step 3: Count distinct procedures within the first 48 hours for the cohort
  procs_in_48h AS (
    SELECT
      c.stay_id,
      COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON c.stay_id = pe.stay_id
    WHERE
      -- Filter procedures to the first 48 hours of the ICU stay
      pe.starttime >= c.intime AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    GROUP BY
      c.stay_id
  ),
  -- Step 4: Combine cohort stats with procedure counts and assign quintiles
  quintiles AS (
    SELECT
      c.stay_id,
      c.hospital_expire_flag,
      c.los,
      COALESCE(p.distinct_procedure_count, 0) AS distinct_procedure_count,
      NTILE(5) OVER (ORDER BY COALESCE(p.distinct_procedure_count, 0)) AS quintile
    FROM
      cohort AS c
    LEFT JOIN
      procs_in_48h AS p
      ON c.stay_id = p.stay_id
  )
-- Step 5: Calculate final metrics per quintile
SELECT
  quintile,
  COUNT(stay_id) AS num_patients,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;