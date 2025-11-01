WITH cohort AS (
  /* One row per admission matching the age, sex, and pneumonia/aspiration criteria */
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    p.subject_id,
    p.gender,
    (CASE
       WHEN p.anchor_age IS NOT NULL THEN
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
     END) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (LOWER(dd.long_title) LIKE '%pneumonia%' OR LOWER(dd.long_title) LIKE '%aspiration%')
    AND (CASE
           WHEN p.anchor_age IS NOT NULL THEN
             p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
         END) BETWEEN 79 AND 89
    AND a.dischtime IS NOT NULL
),
cohort_with_metrics AS (
  SELECT
    c.*,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS LOS_days,
    CASE WHEN c.deathtime IS NOT NULL OR c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS Mort_in_hosp
  FROM cohort AS c
),
flags AS (
  SELECT
    cm.hadm_id,
    cm.admittime,
    cm.dischtime,
    cm.hospital_expire_flag,
    cm.deathtime,
    cm.subject_id,
    cm.gender,
    cm.age_at_adm,
    cm.LOS_days,
    cm.Mort_in_hosp,
    /* Day-1 ICU presence: ICU stay starting within first hospital day */
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = cm.hadm_id
        AND i.intime >= cm.admittime
        AND i.intime < TIMESTAMP_ADD(cm.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS Day1_ICU,
    /* Ventilation presence during stay */
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
      WHERE ce.hadm_id = cm.hadm_id
        AND ce.charttime >= cm.admittime
        AND ce.charttime <= cm.dischtime
        AND (LOWER(di.label) LIKE '%ventilation%' OR LOWER(di.label) LIKE '%ventilator%')
    ) THEN 1 ELSE 0 END AS Vent_present,
    /* Vasopressor presence during stay */
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2
        ON ie.itemid = di2.itemid
      WHERE ie.hadm_id = cm.hadm_id
        AND ie.starttime <= cm.dischtime
        AND ie.endtime >= cm.admittime
        AND (LOWER(di2.label) LIKE '%norepinephrine%' OR LOWER(di2.label) LIKE '%epinephrine%'
             OR LOWER(di2.label) LIKE '%dopamine%' OR LOWER(di2.label) LIKE '%phenylephrine%'
             OR LOWER(di2.label) LIKE '%vasopressin%')
    ) THEN 1 ELSE 0 END AS Vasopressor_present,
    /* Renal replacement therapy / dialysis presence during stay */
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN `physionet-data.mimiciv_3_1_icu.d_items` di3
        ON pe.itemid = di3.itemid
      WHERE pe.hadm_id = cm.hadm_id
        AND (LOWER(di3.label) LIKE '%dialysis%' OR LOWER(di3.label) LIKE '%renal replacement%' OR LOWER(di3.label) LIKE '%hemofiltration%')
    ) THEN 1 ELSE 0 END AS RRT_present
  FROM cohort_with_metrics cm
)
SELECT
  CASE WHEN LOS_days <= 7 THEN '≤7' ELSE '>7' END AS LOS_group,
  COUNT(*) AS n_admissions,
  SUM(Mort_in_hosp) AS deaths,
  ROUND(100.0 * AVG(Mort_in_hosp), 2) AS mortality_percent,
  AVG(Day1_ICU) AS Day1_ICU_rate,
  AVG(Vent_present) AS Vent_rate,
  AVG(Vasopressor_present) AS Vasop_rate,
  AVG(RRT_present) AS RRT_rate
FROM flags
GROUP BY LOS_group
ORDER BY LOS_group;