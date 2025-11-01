WITH patients_filtered AS (
  SELECT p.subject_id,
         p.gender,
         p.anchor_age,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
critical_labs AS (
  SELECT pf.subject_id,
         pf.hadm_id,
         le.itemid
  FROM patients_filtered pf
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pf.subject_id = le.subject_id
   AND pf.hadm_id = le.hadm_id
  WHERE le.flag IS NOT NULL
    AND LOWER(le.flag) LIKE '%critical%'
    AND le.charttime <= DATETIME_ADD(pf.admittime, INTERVAL 72 HOUR)
),
scores AS (
  SELECT subject_id,
         hadm_id,
         COUNT(DISTINCT itemid) AS critical_lab_types
  FROM critical_labs
  GROUP BY subject_id, hadm_id
),
target_stats AS (
  SELECT
    MAX(s.critical_lab_types) AS max_instability_score,
    COUNTIF(s.critical_lab_types > 0) / COUNT(*) AS critical_event_rate,
    AVG(DATETIME_DIFF(pf.dischtime, pf.admittime, DAY)) AS avg_los_days,
    AVG(pf.hospital_expire_flag) AS mortality_rate
  FROM patients_filtered pf
  LEFT JOIN scores s
    ON pf.subject_id = s.subject_id
   AND pf.hadm_id = s.hadm_id
),
general_patients AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
general_critical_labs AS (
  SELECT gp.subject_id,
         gp.hadm_id,
         le.itemid
  FROM general_patients gp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gp.subject_id = le.subject_id
   AND gp.hadm_id = le.hadm_id
  WHERE le.flag IS NOT NULL
    AND LOWER(le.flag) LIKE '%critical%'
    AND le.charttime <= DATETIME_ADD(gp.admittime, INTERVAL 72 HOUR)
),
general_scores AS (
  SELECT subject_id,
         hadm_id,
         COUNT(DISTINCT itemid) AS critical_lab_types
  FROM general_critical_labs
  GROUP BY subject_id, hadm_id
),
general_stats AS (
  SELECT
    COUNTIF(critical_lab_types > 0) / COUNT(*) AS critical_event_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM general_patients gp
  LEFT JOIN general_scores gs
    ON gp.subject_id = gs.subject_id
   AND gp.hadm_id = gs.hadm_id
)
SELECT
  ts.max_instability_score AS target_max_instability_score,
  ts.critical_event_rate AS target_critical_event_rate,
  ts.avg_los_days AS target_avg_los_days,
  ts.mortality_rate AS target_mortality_rate,
  gs.critical_event_rate AS general_critical_event_rate,
  gs.avg_los_days AS general_avg_los_days,
  gs.mortality_rate AS general_mortality_rate
FROM target_stats ts
CROSS JOIN general_stats gs;