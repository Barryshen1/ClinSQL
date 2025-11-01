WITH pneumonia_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
     AND a.subject_id = d.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
), los_flagged AS (
  SELECT
    *,
    CASE
      WHEN los_days <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group
  FROM
    pneumonia_cohort
), day1_icu AS (
  SELECT
    l.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE
        i.hadm_id = l.hadm_id
        AND i.intime BETWEEN l.admittime AND TIMESTAMP_ADD(l.admittime, INTERVAL 1 DAY)
    ) AS day1_icu_flag
  FROM los_flagged l
), interventions AS (
  SELECT
    d1.hadm_id,
    -- Mechanical ventilation within day 1
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
        ON pe.stay_id = s.stay_id
      WHERE
        s.hadm_id = d1.hadm_id
        AND pe.starttime BETWEEN d1.admittime AND TIMESTAMP_ADD(d1.admittime, INTERVAL 1 DAY)
        AND LOWER(pe.ordercategorydescription) LIKE '%ventil%'
    ) AS mechvent_flag,
    -- Vasopressors within day 1
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
        ON ie.stay_id = s.stay_id
      WHERE
        s.hadm_id = d1.hadm_id
        AND ie.starttime BETWEEN d1.admittime AND TIMESTAMP_ADD(d1.admittime, INTERVAL 1 DAY)
        AND LOWER(ie.ordercategoryname) LIKE '%pressor%'
    ) AS vasopressor_flag,
    -- RRT within day 1
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie2
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` s2
        ON ie2.stay_id = s2.stay_id
      WHERE
        s2.hadm_id = d1.hadm_id
        AND ie2.starttime BETWEEN d1.admittime AND TIMESTAMP_ADD(d1.admittime, INTERVAL 1 DAY)
        AND (
          LOWER(ie2.ordercategoryname) LIKE '%renal%'
          OR LOWER(ie2.ordercategoryname) LIKE '%rrt%'
        )
    ) AS rrt_flag
  FROM
    day1_icu d1
), analysis_prep AS (
  SELECT
    d1.los_group,
    d1.day1_icu_flag,
    d1.hospital_expire_flag,
    i.mechvent_flag,
    i.vasopressor_flag,
    i.rrt_flag
  FROM
    day1_icu d1
    JOIN interventions i
      ON d1.hadm_id = i.hadm_id
)
SELECT
  los_group,
  IF(day1_icu_flag, 'Yes', 'No') AS day1_icu,
  COUNT(*) AS n_patients,
  ROUND(100.0 * AVG(hospital_expire_flag), 1) AS mortality_pct,
  ROUND(100.0 * AVG(IF(mechvent_flag, 1, 0)), 1) AS mechvent_pct,
  ROUND(100.0 * AVG(IF(vasopressor_flag, 1, 0)), 1) AS vasopressor_pct,
  ROUND(100.0 * AVG(IF(rrt_flag, 1, 0)), 1) AS rrt_pct
FROM
  analysis_prep
GROUP BY
  los_group,
  day1_icu_flag
ORDER BY
  los_group,
  day1_icu_flag;