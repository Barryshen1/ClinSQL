WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      (d_dx.icd_version = 9 AND d_dx.icd_code = '78551')
      OR
      (d_dx.icd_version = 10 AND d_dx.icd_code = 'R570')
    )
),

proc_counts AS (
  SELECT
    c.stay_id,
    c.hosp_los_days,
    c.hospital_expire_flag,
    COUNT(pe.itemid) AS proc_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
  WHERE
    pe.starttime >= c.intime
    AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 1 DAY)
  GROUP BY
    c.stay_id, c.hosp_los_days, c.hospital_expire_flag
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS proc_quintile
  FROM
    proc_counts
)

SELECT
  proc_quintile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(hosp_los_days) AS mean_hosp_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hosp_mortality_percent
FROM
  quintiles
GROUP BY
  proc_quintile
ORDER BY
  proc_quintile;