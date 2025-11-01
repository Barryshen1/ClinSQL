WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS hospital_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND LOWER(ddx.long_title) LIKE '%asthma%'
    AND LOWER(ddx.long_title) LIKE '%exacerbation%'
    AND icu.intime >= adm.admittime
    AND icu.intime <= adm.dischtime
),

first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    hospital_los,
    hospital_expire_flag
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM cohort
  ) t
  WHERE rn = 1
),

procedures_first_72h AS (
  SELECT
    f.stay_id,
    COUNT(proc.itemid) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON f.stay_id = proc.stay_id
  WHERE
    proc.starttime >= f.intime
    AND proc.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.stay_id
),

quartiles AS (
  SELECT
    p.stay_id,
    p.procedure_count,
    f.hospital_los,
    f.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY p.procedure_count) AS quartile
  FROM
    procedures_first_72h p
  JOIN
    first_icu_stays f
    ON p.stay_id = f.stay_id
)

SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM
  quartiles
GROUP BY
  quartile
ORDER BY
  quartile;