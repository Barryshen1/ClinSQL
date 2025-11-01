WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY icu.intime) AS rn_first_icu
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    a.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
  ON
    dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND dx.seq_num = 1
    AND dx.icd_version = 10
    AND dx.icd_code LIKE 'I21%'
),

first_icu AS (
  SELECT *
  FROM cohort
  WHERE rn_first_icu = 1
),

procedures_72h AS (
  SELECT
    f.hadm_id,
    f.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    first_icu f
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    f.stay_id = pe.stay_id
    AND pe.starttime >= f.icu_intime
    AND pe.starttime <= DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    f.hadm_id, f.stay_id
),

quartiles AS (
  SELECT
    f.*,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    NTILE(4) OVER (ORDER BY COALESCE(p.procedure_count, 0)) AS procedure_quartile
  FROM
    first_icu f
  LEFT JOIN
    procedures_72h p
  ON
    f.hadm_id = p.hadm_id
)

SELECT
  procedure_quartile,
  COUNT(*) AS n_patients,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM
  quartiles
GROUP BY
  procedure_quartile
ORDER BY
  procedure_quartile;