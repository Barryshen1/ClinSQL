WITH
-- Get ICH patients (ICD-9: 430-432, ICD-10: I60-I62)
ich_patients AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
    OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I62')
),

-- Get first ICU stay for each patient
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) / 24 AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  WHERE
    s.subject_id IN (SELECT subject_id FROM ich_patients)
),

-- Filter to only first ICU stays
ich_first_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime,
    icu_los_days
  FROM
    first_icu_stays
  WHERE
    stay_rank = 1
),

-- Get procedure burden in first 72 hours
procedure_burden AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN
    ich_first_stays s
  ON
    p.subject_id = s.subject_id
    AND p.hadm_id = s.hadm_id
    AND p.stay_id = s.stay_id
  WHERE
    TIMESTAMP_DIFF(p.starttime, s.icu_intime, HOUR) <= 72
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
),

-- Get patient demographics for ICH group
ich_group AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    s.icu_los_days,
    pb.procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    ich_first_stays s
  ON
    p.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
  JOIN
    procedure_burden pb
  ON
    p.subject_id = pb.subject_id
    AND a.hadm_id = pb.hadm_id
    AND s.stay_id = pb.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
),

-- Get general ICU population (excluding ICH patients)
general_icu_population AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    s.icu_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    (
      SELECT
        subject_id,
        hadm_id,
        intime,
        outtime,
        TIMESTAMP_DIFF(outtime, intime, HOUR) / 24 AS icu_los_days,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
    ) s
  ON
    p.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
  WHERE
    p.subject_id NOT IN (SELECT subject_id FROM ich_patients)
    AND s.stay_rank = 1
)

-- Final results
SELECT
  -- ICH group metrics
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS ich_75th_percentile_procedure_burden,
  AVG(icu_los_days) AS ich_mean_icu_los,
  AVG(CAST(hospital_expire_flag AS INT64)) AS ich_hospital_mortality,

  -- General ICU population metrics
  (SELECT AVG(icu_los_days) FROM general_icu_population) AS general_mean_icu_los,
  (SELECT AVG(CAST(hospital_expire_flag AS INT64)) FROM general_icu_population) AS general_hospital_mortality

FROM
  ich_group
LIMIT 1;