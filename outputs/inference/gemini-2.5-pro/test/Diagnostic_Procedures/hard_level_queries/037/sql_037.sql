WITH
  SepsisHadm AS (
    -- Identify hospital admissions with a sepsis diagnosis
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code IN ('99591', '99592')) -- Sepsis, Severe Sepsis
      OR (
        icd_version = 10 AND (
          icd_code LIKE 'A41%' -- Other sepsis
          OR icd_code IN ('R6520', 'R6521') -- Severe sepsis
        )
      )
  ),
  Stays AS (
    -- Define the two cohorts: Sepsis vs. Non-Sepsis female patients aged 53-63
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag,
      CASE
        WHEN s.hadm_id IS NOT NULL THEN 'Sepsis'
        ELSE 'Non-Sepsis Control'
      END AS cohort
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON icu.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
    LEFT JOIN
      SepsisHadm AS s ON icu.hadm_id = s.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 53 AND 63
  ),
  ProcedureCounts AS (
    -- Count the number of procedures in the first 24 hours of each ICU stay
    SELECT
      s.stay_id,
      COUNT(pe.itemid) AS num_procedures
    FROM
      Stays AS s
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON s.stay_id = pe.stay_id
    WHERE
      -- Filter for procedures within the first 24 hours of ICU admission
      pe.starttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
    GROUP BY
      s.stay_id
  )
-- Final aggregation to calculate and compare metrics between cohorts
SELECT
  s.cohort,
  COUNT(DISTINCT s.stay_id) AS number_of_stays,
  -- Use COALESCE to correctly handle stays with 0 procedures
  APPROX_QUANTILES(COALESCE(pc.num_procedures, 0), 100)[OFFSET(75)] AS procedures_first24h_p75,
  APPROX_QUANTILES(COALESCE(pc.num_procedures, 0), 100)[OFFSET(90)] AS procedures_first24h_p90,
  AVG(s.los) AS avg_icu_los_days,
  AVG(s.hospital_expire_flag) AS hospital_mortality_rate
FROM
  Stays AS s
LEFT JOIN
  ProcedureCounts AS pc ON s.stay_id = pc.stay_id
GROUP BY
  s.cohort
ORDER BY
  s.cohort DESC;