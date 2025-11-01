WITH age_matched_males AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

ami_icu_stays AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
  ON
    dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    (ddx.icd_code LIKE '410%' AND ddx.icd_version = 9)
    OR (ddx.icd_code LIKE 'I21%' AND ddx.icd_version = 10)
),

procedure_counts AS (
  SELECT
    a.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM
    ami_icu_stays a
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    a.stay_id = pe.stay_id
  WHERE
    pe.starttime >= a.intime
    AND pe.starttime <= DATETIME_ADD(a.intime, INTERVAL 72 HOUR)
  GROUP BY
    a.stay_id
),

diagnostic_intensity AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 10)[OFFSET(9)] AS percentile_90_procedure_count
  FROM
    procedure_counts
),

outcome_all AS (
  SELECT
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) / 24 AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality
  FROM
    age_matched_males
)

SELECT
  di.percentile_90_procedure_count,
  o.mean_los_days,
  o.in_hospital_mortality
FROM
  diagnostic_intensity di
CROSS JOIN
  outcome_all o;