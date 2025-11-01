WITH first_icu AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
filtered_first_icu AS (
  SELECT * FROM first_icu WHERE rn = 1
),
procedure_counts AS (
  SELECT
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM filtered_first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id
),
quintiles AS (
  SELECT
    f.stay_id,
    f.los,
    f.hospital_expire_flag,
    pc.procedure_count,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS quintile
  FROM filtered_first_icu f
  LEFT JOIN procedure_counts pc
    ON f.stay_id = pc.stay_id
)
SELECT
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quintiles
GROUP BY quintile
ORDER BY quintile;