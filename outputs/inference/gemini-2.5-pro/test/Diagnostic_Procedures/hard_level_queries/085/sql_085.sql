WITH
  -- Step 1: Identify first ICU stays for female patients aged 87-97
  first_stays AS (
    SELECT
      p.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.los,
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i ON p.subject_id = i.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 87 AND 97
  ),
  -- Step 2: Filter the cohort for patients with a Lower GI Bleeding diagnosis
  gi_bleed_stays AS (
    SELECT DISTINCT -- Ensure one row per stay, even with multiple relevant diagnoses
      fs.subject_id,
      fs.hadm_id,
      fs.stay_id,
      fs.intime,
      fs.los
    FROM
      first_stays AS fs
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON fs.hadm_id = dx.hadm_id
    WHERE
      fs.rn = 1 -- Filter for the first ICU stay only
      AND (
        (dx.icd_version = 9 AND dx.icd_code IN ('578.1', '578.9', '569.3'))
        OR (dx.icd_version = 10 AND dx.icd_code IN ('K92.1', 'K92.2', 'K62.5'))
      )
  ),
  -- Step 3: Count distinct procedures in the first 48 hours for each stay
  proc_counts AS (
    SELECT
      gs.hadm_id,
      gs.los,
      COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM
      gi_bleed_stays AS gs
    LEFT JOIN -- Use LEFT JOIN to include patients with 0 procedures
      `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON gs.stay_id = pe.stay_id AND pe.starttime BETWEEN gs.intime AND TIMESTAMP_ADD(gs.intime, INTERVAL 48 HOUR)
    GROUP BY
      gs.hadm_id,
      gs.los
  ),
  -- Step 4: Add mortality data and stratify patients into quintiles based on procedure count
  patient_quintiles AS (
    SELECT
      pc.distinct_procedure_count,
      pc.los,
      a.hospital_expire_flag,
      NTILE(5) OVER (
        ORDER BY
          pc.distinct_procedure_count
      ) AS procedure_quintile
    FROM
      proc_counts AS pc
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON pc.hadm_id = a.hadm_id
  )
-- Step 5: Final aggregation to calculate metrics for each quintile
SELECT
  procedure_quintile,
  COUNT(*) AS num_patients,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM
  patient_quintiles
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;