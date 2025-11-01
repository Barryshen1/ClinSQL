WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(i.outtime, i.intime, SECOND) / 86400.0 AS icu_los_days,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    i.stay_id IN (
      SELECT
        stay_id
      FROM
        physionet-data.mimiciv_3_1_icu.icustays
      QUALIFY
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
    )
),
filtered_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    f.stay_id,
    f.intime,
    f.icu_los_days,
    f.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    first_icu_stays f
  ON
    p.subject_id = f.subject_id
  WHERE
    p.anchor_age BETWEEN 37 AND 47
    AND p.gender = 'M'
),
procedures_first_48h AS (
  SELECT
    f.subject_id,
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM
    filtered_patients f
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents pe
  ON
    f.stay_id = pe.stay_id
  WHERE
    pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY
    f.subject_id, f.stay_id
),
quintile_data AS (
  SELECT
    p.*,
    COALESCE(pr.procedure_count, 0) AS procedure_count,
    NTILE(5) OVER (ORDER BY COALESCE(pr.procedure_count, 0)) AS quintile
  FROM
    filtered_patients p
  LEFT JOIN
    procedures_first_48h pr
  ON
    p.stay_id = pr.stay_id
)
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  quintile_data
GROUP BY
  quintile
ORDER BY
  quintile;