WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (
      PARTITION BY icu.hadm_id
      ORDER BY icu.intime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
),
dka_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_version = 9
    AND d.icd_code LIKE '2501%'  -- DKA ICD-9 codes 250.1x
),
procedures_24h AS (
  SELECT
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN first_icu icu
      ON pe.subject_id = icu.subject_id
     AND pe.hadm_id    = icu.hadm_id
     AND pe.stay_id    = icu.stay_id
     AND icu.rn = 1
  WHERE
    pe.starttime BETWEEN icu.intime
                     AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    pe.stay_id
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COALESCE(p24.proc_count, 0) AS procedure_count,
    icu.los,
    adm.hospital_expire_flag
  FROM
    first_icu icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    JOIN dka_admissions dka
      ON icu.subject_id = dka.subject_id
     AND icu.hadm_id    = dka.hadm_id
    LEFT JOIN procedures_24h p24
      ON icu.stay_id = p24.stay_id
  WHERE
    icu.rn = 1
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
),
with_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    cohort
)
SELECT
  quintile,
  COUNT(*) AS num_stays,
  ROUND(AVG(procedure_count),2) AS mean_proc_count,
  MIN(procedure_count)     AS min_proc_count,
  MAX(procedure_count)     AS max_proc_count,
  ROUND(AVG(los), 2)       AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_pct
FROM
  with_quintiles
GROUP BY
  quintile
ORDER BY
  quintile;