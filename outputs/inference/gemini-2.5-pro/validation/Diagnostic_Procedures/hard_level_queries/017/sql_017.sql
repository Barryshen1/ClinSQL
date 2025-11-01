WITH first_icu_stay AS (
  -- This CTE identifies the first ICU stay for each patient and gathers baseline data.
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.los,
    ROW_NUMBER() OVER(PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
),
sepsis_cohort AS (
  -- This CTE filters for male patients aged 83-93 who had a sepsis diagnosis during their first ICU stay.
  SELECT DISTINCT
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.intime,
    fis.los,
    fis.hospital_expire_flag
  FROM first_icu_stay AS fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON fis.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    fis.rn = 1 -- Filter for the first ICU stay only
    AND fis.gender = 'M' -- Filter for male patients
    AND (EXTRACT(YEAR FROM fis.admittime) - fis.anchor_year + fis.anchor_age) BETWEEN 83 AND 93 -- Filter for age
    AND LOWER(ddx.long_title) LIKE '%sepsis%' -- Filter for sepsis diagnosis
),
procedure_counts AS (
  -- This CTE counts the number of distinct procedures for each patient in the cohort within the first 72 hours.
  SELECT
    sc.subject_id,
    sc.stay_id,
    sc.los,
    sc.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM sepsis_cohort AS sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON sc.stay_id = pe.stay_id
    AND pe.starttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 72 HOUR) -- Within the first 72 hours of ICU admission
  GROUP BY
    sc.subject_id,
    sc.stay_id,
    sc.los,
    sc.hospital_expire_flag
),
procedure_quartiles AS (
  -- This CTE assigns each patient to a quartile based on their procedure count.
  SELECT
    pc.procedure_count,
    pc.los,
    pc.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
  FROM procedure_counts AS pc
)
-- Final query to calculate and report the metrics per quartile.
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS NUMERIC)) * 100 AS mortality_percentage
FROM procedure_quartiles
GROUP BY
  quartile
ORDER BY
  quartile;