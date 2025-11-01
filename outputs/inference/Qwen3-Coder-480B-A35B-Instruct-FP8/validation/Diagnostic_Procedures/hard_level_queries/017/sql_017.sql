WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE i.stay_id IN (
    SELECT stay_id
    FROM (
      SELECT
        subject_id,
        stay_id,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    )
    WHERE rn = 1
  )
),
sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%sepsis%'
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
first_icu_sepsis AS (
  SELECT f.*
  FROM first_icu_stays f
  JOIN sepsis_admissions s ON f.hadm_id = s.hadm_id
  JOIN eligible_patients ep ON f.subject_id = ep.subject_id
),
procedure_counts AS (
  SELECT
    f.stay_id,
    f.los,
    f.hospital_expire_flag,
    COUNT(DISTINCT p.itemid) AS distinct_procedures
  FROM first_icu_sepsis f
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id
    AND p.starttime >= f.intime
    AND p.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.stay_id, f.los, f.hospital_expire_flag
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY distinct_procedures) AS procedure_quartile
  FROM procedure_counts
)
SELECT
  procedure_quartile,
  AVG(distinct_procedures) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;