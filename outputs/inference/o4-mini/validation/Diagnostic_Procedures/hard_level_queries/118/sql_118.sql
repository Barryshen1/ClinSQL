WITH female_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),
ami_hadm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),
first_icu_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
  WHERE
    icu.rn = 1
),
proc_counts AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(pe.starttime) AS proc_count
  FROM
    first_icu_stay icu
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON pe.stay_id = icu.stay_id
      AND pe.hadm_id = icu.hadm_id
      AND pe.starttime >= icu.intime
      AND pe.starttime < TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
),
cohort AS (
  SELECT
    pc.*,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    proc_counts pc
    JOIN female_patients fp
      ON pc.subject_id = fp.subject_id
    JOIN ami_hadm am
      ON pc.subject_id = am.subject_id
      AND pc.hadm_id = am.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pc.hadm_id = a.hadm_id
),
ranked AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY proc_count) AS quartile
  FROM
    cohort
)
SELECT
  quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  ROUND(AVG(los_days), 2) AS mean_hospital_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_pct
FROM
  ranked
GROUP BY
  quartile
ORDER BY
  quartile;