WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON icu.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      (dx.icd_version = 10 AND dx.icd_code = 'I514') OR
      (dx.icd_version = 9 AND dx.icd_code = '78551')
    )
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    COUNT(*) AS procedure_count
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON c.subject_id = pe.subject_id
      AND c.hadm_id = pe.hadm_id
      AND c.stay_id = pe.stay_id
      AND pe.starttime >= c.intime
      AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime
),
adm_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),
final AS (
  SELECT
    pc.*,
    ad.hospital_los,
    ad.hospital_expire_flag
  FROM
    proc_counts pc
    INNER JOIN adm_data ad
      ON pc.subject_id = ad.subject_id
      AND pc.hadm_id = ad.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    final
)
SELECT
  quintile,
  COUNT(*) AS n_stays,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(hospital_los),2) AS mean_hospital_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS in_hospital_mortality_percent
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;