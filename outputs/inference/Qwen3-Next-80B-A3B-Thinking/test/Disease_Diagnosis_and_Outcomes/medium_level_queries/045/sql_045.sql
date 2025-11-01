WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND di.long_title LIKE '%pneumonia%'
    )
),

icu_day1 AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(CASE WHEN i.intime <= c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END), 0) AS icu_day1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  GROUP BY c.hadm_id
),

mech_vent AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(CASE WHEN pe.starttime <= c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END), 0) AS mech_vent_day1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.hadm_id = pe.hadm_id
  WHERE pe.itemid = 223848
  GROUP BY c.hadm_id
),

vasopressors AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(CASE WHEN ie.starttime <= c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END), 0) AS vasopressor_day1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.hadm_id = ie.hadm_id
  WHERE ie.itemid IN (221906, 222315, 221289, 221662, 221905)
  GROUP BY c.hadm_id
),

rrt AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(CASE WHEN pe.starttime <= c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END), 0) AS rrt_day1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.hadm_id = pe.hadm_id
  WHERE pe.itemid IN (225800, 225801, 225802, 225803, 225804, 225805)
  GROUP BY c.hadm_id
)

SELECT
  CASE WHEN los_days <= 7 THEN 'LOS <=7' ELSE 'LOS >7' END AS los_category,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(icu_day1) AS icu_day1_prevalence,
  AVG(mech_vent_day1) AS mech_vent_prevalence,
  AVG(vasopressor_day1) AS vasopressor_prevalence,
  AVG(rrt_day1) AS rrt_prevalence
FROM cohort c
LEFT JOIN icu_day1 i ON c.hadm_id = i.hadm_id
LEFT JOIN mech_vent mv ON c.hadm_id = mv.hadm_id
LEFT JOIN vasopressors v ON c.hadm_id = v.hadm_id
LEFT JOIN rrt r ON c.hadm_id = r.hadm_id
GROUP BY los_category;