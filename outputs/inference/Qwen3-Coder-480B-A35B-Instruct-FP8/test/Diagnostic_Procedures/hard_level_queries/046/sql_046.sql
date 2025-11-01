WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE
    i.intime = (
      SELECT MIN(intime)
      FROM physionet-data.mimiciv_3_1_icu.icustays i2
      WHERE i2.subject_id = i.subject_id
    )
),

target_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND dd.icd_code = 'J80'
    AND dd.icd_version = 10
),

target_first_stays AS (
  SELECT
    f.*
  FROM
    first_icu_stays f
  JOIN
    target_patients t
    ON f.subject_id = t.subject_id
),

procedures_first_72hr AS (
  SELECT
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN
    first_icu_stays f
    ON pe.stay_id = f.stay_id
  WHERE
    pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    pe.stay_id
),

target_procedures AS (
  SELECT
    t.stay_id,
    COALESCE(p.proc_count, 0) AS proc_count
  FROM
    target_first_stays t
  LEFT JOIN
    procedures_first_72hr p
    ON t.stay_id = p.stay_id
),

all_procedures AS (
  SELECT
    f.stay_id,
    COALESCE(p.proc_count, 0) AS proc_count,
    f.hospital_los,
    f.hospital_expire_flag
  FROM
    first_icu_stays f
  LEFT JOIN
    procedures_first_72hr p
    ON f.stay_id = p.stay_id
)

SELECT
  -- Target cohort stats
  (SELECT MIN(proc_count) FROM target_procedures) AS min_procedures_target,

  -- All ICU patients percentiles
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_all,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS p90_all,

  -- Mean hospital LOS
  AVG(hospital_los) AS mean_hospital_los,

  -- In-hospital mortality
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  all_procedures;