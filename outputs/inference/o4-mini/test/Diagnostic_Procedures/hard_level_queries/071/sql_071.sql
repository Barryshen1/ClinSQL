WITH ich_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
),
female_50_60 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),
ich_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN ich_admissions ia
      ON icu.subject_id = ia.subject_id
      AND icu.hadm_id = ia.hadm_id
    JOIN female_50_60 f
      ON icu.subject_id = f.subject_id
),
all_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
per_stay_metrics AS (
  SELECT
    s.cohort,
    s.stay_id,
    -- Count procedures in first 72h using starttime
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = s.stay_id
        AND pe.starttime BETWEEN s.intime
          AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    ), 0) AS procedure_count,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag AS mortality
  FROM (
    SELECT
      stay_id,
      'ICH_Female_50_60' AS cohort,
      subject_id,
      hadm_id,
      intime
    FROM ich_icu_stays
    UNION ALL
    SELECT
      stay_id,
      'All_ICU' AS cohort,
      subject_id,
      hadm_id,
      intime
    FROM all_icu_stays
  ) s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
),
final_stats AS (
  SELECT
    cohort,
    -- Procedure burden percentiles and max
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS proc_p25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS proc_p50,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS proc_p90,
    MAX(procedure_count) AS proc_max,
    -- Median LOS
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median,
    -- Mortality rate
    AVG(mortality) AS mortality_rate
  FROM per_stay_metrics
  GROUP BY cohort
)
SELECT
  cohort,
  proc_p25,
  proc_p50,
  proc_p90,
  proc_max,
  los_median,
  mortality_rate
FROM final_stats
ORDER BY cohort;