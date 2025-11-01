WITH first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
)
, eligible_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM
    first_icu_stays f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
  WHERE
    f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
)
, ich_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrhage%'
)
, procedure_burden AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    COUNT(DISTINCT pr.icd_code) AS procedure_burden
  FROM
    eligible_patients e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON e.subject_id = pr.subject_id
      AND e.hadm_id = pr.hadm_id
      AND pr.chartdate >= DATE(e.intime)
      AND pr.chartdate < DATE_ADD(DATE(e.intime), INTERVAL 3 DAY)
  GROUP BY
    e.subject_id, e.hadm_id, e.stay_id
)
, cohort_ich AS (
  SELECT
    pb.subject_id,
    pb.hadm_id,
    pb.stay_id,
    pb.procedure_burden
  FROM
    procedure_burden pb
    JOIN ich_admissions ich
      ON pb.subject_id = ich.subject_id AND pb.hadm_id = ich.hadm_id
)
, cohort_general AS (
  SELECT
    pb.subject_id,
    pb.hadm_id,
    pb.stay_id,
    pb.procedure_burden
  FROM
    procedure_burden pb
)
, icu_los_mortality AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.los,
    a.hospital_expire_flag
  FROM
    eligible_patients e
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON e.hadm_id = a.hadm_id
)
-- Final aggregation
SELECT
  'ICH cohort' AS cohort,
  APPROX_QUANTILES(c.procedure_burden, 4)[3] AS procedure_burden_75th_percentile,
  AVG(l.los) AS mean_icu_los,
  AVG(CAST(l.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  cohort_ich c
  JOIN icu_los_mortality l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id AND c.stay_id = l.stay_id

UNION ALL

SELECT
  'General ICU population' AS cohort,
  NULL AS procedure_burden_75th_percentile,
  AVG(l.los) AS mean_icu_los,
  AVG(CAST(l.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  cohort_general c
  JOIN icu_los_mortality l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id AND c.stay_id = l.stay_id
  WHERE
    -- Exclude ICH cohort from general population
    NOT EXISTS (
      SELECT 1
      FROM ich_admissions ich
      WHERE c.subject_id = ich.subject_id AND c.hadm_id = ich.hadm_id
    );