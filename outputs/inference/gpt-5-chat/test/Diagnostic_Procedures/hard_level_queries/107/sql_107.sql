WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    i.intime,
    i.outtime,
    i.los
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN (
    -- first ICU stay per admission
    SELECT ic.subject_id, ic.hadm_id, ic.stay_id, ic.intime, ic.outtime, ic.los
    FROM physionet-data.mimiciv_3_1_icu.icustays ic
    JOIN (
      SELECT hadm_id, MIN(intime) AS first_intime
      FROM physionet-data.mimiciv_3_1_icu.icustays
      GROUP BY hadm_id
    ) first_ic
      ON ic.hadm_id = first_ic.hadm_id AND ic.intime = first_ic.first_intime
  ) i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.hadm_id IN (
      SELECT di.hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    )
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
cohort_with_counts AS (
  SELECT
    c.*,
    pc.procedure_count
  FROM cohort c
  JOIN proc_counts pc
    ON c.stay_id = pc.stay_id
),
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    procedure_count,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY procedure_count) AS proc_quartile
  FROM cohort_with_counts
)
SELECT
  proc_quartile AS quartile,
  COUNT(*) AS N,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_percent
FROM quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;