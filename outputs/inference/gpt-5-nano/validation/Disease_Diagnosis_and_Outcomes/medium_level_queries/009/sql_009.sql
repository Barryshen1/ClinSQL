WITH sepsis_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      LOWER(dd.long_title) LIKE '%sepsis%' OR
      LOWER(dd.long_title) LIKE '%sept%'  -- catch sepsis-related terms
    )
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'  -- exclude septic shock
),
flags AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.stay_id,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag,
    CASE WHEN TIMESTAMP_DIFF(sc.dischtime, sc.admittime, DAY) < 8 THEN 0 ELSE 1 END AS los_ge_8,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
      WHERE ce.subject_id = sc.subject_id
        AND ce.hadm_id = sc.hadm_id
        AND ce.stay_id = sc.stay_id
        AND ce.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
        AND LOWER(di.label) LIKE '%ventilat%'
    ) THEN 1 ELSE 0 END AS vent_day1,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
      WHERE ce.subject_id = sc.subject_id
        AND ce.hadm_id = sc.hadm_id
        AND ce.stay_id = sc.stay_id
        AND ce.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
        AND (
          LOWER(di.label) LIKE '%vasopressor%' OR
          LOWER(di.label) LIKE '%norepinephrine%' OR
          LOWER(di.label) LIKE '%epinephrine%' OR
          LOWER(di.label) LIKE '%phenylephrine%' OR
          LOWER(di.label) LIKE '%dopamine%'
        )
    ) THEN 1 ELSE 0 END AS vasop_day1,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
      WHERE ce.subject_id = sc.subject_id
        AND ce.hadm_id = sc.hadm_id
        AND ce.stay_id = sc.stay_id
        AND ce.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 1 DAY)
        AND (
          LOWER(di.label) LIKE '%dialysis%' OR
          LOWER(di.label) LIKE '%renal%' OR
          LOWER(di.label) LIKE '%hemodialysis%'
        )
    ) THEN 1 ELSE 0 END AS rrt_day1
  FROM sepsis_cohort sc
)
SELECT
  CASE WHEN los_ge_8 = 0 THEN '<8' ELSE '>=8' END AS los_group,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_percent,
  SUM(vent_day1) * 100.0 / COUNT(*) AS vent_day1_percent,
  SUM(vasop_day1) * 100.0 / COUNT(*) AS vasop_day1_percent,
  SUM(rrt_day1) * 100.0 / COUNT(*) AS rrt_day1_percent,
  COUNT(*) AS n
FROM flags
GROUP BY CASE WHEN los_ge_8 = 0 THEN '<8' ELSE '>=8' END
ORDER BY los_group;