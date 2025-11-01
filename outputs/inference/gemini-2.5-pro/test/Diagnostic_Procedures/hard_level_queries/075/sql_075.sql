WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of Diabetic Ketoacidosis (DKA)
  dka_hadm_ids AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx ON dx.icd_code = d_dx.icd_code
      AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%diabetic ketoacidosis%'
  ),
  -- Step 2 & 3: Filter for male patients (age 39-49) with DKA and identify their first ICU stay
  first_icu_stays AS (
    SELECT
      icu.stay_id,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag,
      ROW_NUMBER() OVER (
        PARTITION BY
          icu.hadm_id
        ORDER BY
          icu.intime
      ) AS icu_stay_rank
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON pat.subject_id = adm.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON adm.hadm_id = icu.hadm_id
      INNER JOIN dka_hadm_ids ON adm.hadm_id = dka_hadm_ids.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 39 AND 49
  ),
  -- Step 4: For each first ICU stay, count distinct procedures within the first 24 hours
  proc_counts_24h AS (
    SELECT
      fis.stay_id,
      fis.los,
      fis.hospital_expire_flag,
      COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM
      first_icu_stays AS fis
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON fis.stay_id = pe.stay_id
      AND pe.starttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 24 HOUR)
    WHERE
      fis.icu_stay_rank = 1
    GROUP BY
      fis.stay_id,
      fis.los,
      fis.hospital_expire_flag
  ),
  -- Step 5: Stratify stays into quintiles based on the procedure count
  stay_quintiles AS (
    SELECT
      stay_id,
      los,
      hospital_expire_flag,
      distinct_procedure_count,
      NTILE(5) OVER (
        ORDER BY
          distinct_procedure_count
      ) AS procedure_quintile
    FROM
      proc_counts_24h
  )
  -- Step 6: Aggregate metrics by quintile and present the final results
SELECT
  procedure_quintile,
  COUNT(stay_id) AS number_of_stays,
  MIN(distinct_procedure_count) AS min_procedure_count,
  MAX(distinct_procedure_count) AS max_procedure_count,
  ROUND(AVG(distinct_procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_percent
FROM
  stay_quintiles
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;