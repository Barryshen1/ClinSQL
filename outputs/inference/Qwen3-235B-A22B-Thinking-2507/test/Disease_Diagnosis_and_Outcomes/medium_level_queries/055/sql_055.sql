WITH complications AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code >= '996' AND icd_code < '1000')
    OR (icd_version = 10 AND icd_code LIKE 'T8%')
),
patients_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
),
cohort AS (
  SELECT pc.*
  FROM patients_cohort pc
  INNER JOIN complications c
    ON pc.hadm_id = c.hadm_id
),
admissions_with_icu AS (
  SELECT 
    c.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
),
admissions_with_features AS (
  SELECT 
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM admissions_with_icu
  WHERE dischtime IS NOT NULL  -- Ensure valid LOS
),
mech_vent_hadm AS (
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilator%' 
     OR LOWER(di.label) LIKE '%ventilation%'
),
vasopressor_hadm AS (
  SELECT DISTINCT ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%norepinephrine%' 
     OR LOWER(di.label) LIKE '%dopamine%' 
     OR LOWER(di.label) LIKE '%epinephrine%' 
     OR LOWER(di.label) LIKE '%phenylephrine%' 
     OR LOWER(di.label) LIKE '%vasopressin%' 
     OR LOWER(di.label) LIKE '%dobutamine%' 
     OR LOWER(di.label) LIKE '%milrinone%' 
     OR LOWER(di.label) LIKE '%vasopressor%'
),
rrt_hadm AS (
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%' 
     OR LOWER(di.label) LIKE '%rrt%' 
     OR LOWER(di.label) LIKE '%renal replacement%'
),
admissions_with_all_features AS (
  SELECT 
    af.*,
    CASE WHEN af.icu_flag = 1 AND mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent,
    CASE WHEN af.icu_flag = 1 AND vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor,
    CASE WHEN af.icu_flag = 1 AND rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt
  FROM admissions_with_features af
  LEFT JOIN mech_vent_hadm mv ON af.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_hadm vp ON af.hadm_id = vp.hadm_id
  LEFT JOIN rrt_hadm rrt ON af.hadm_id = rrt.hadm_id
),
quartiles AS (
  SELECT 
    icu_flag,
    NTILE(4) OVER (PARTITION BY icu_flag ORDER BY los) AS los_quartile,
    hospital_expire_flag,
    mech_vent,
    vasopressor,
    rrt
  FROM admissions_with_all_features
),
quartile_stats AS (
  SELECT
    icu_flag,
    los_quartile,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(mech_vent) AS mech_vent_pct,
    AVG(vasopressor) AS vasopressor_pct,
    AVG(rrt) AS rrt_pct
  FROM quartiles
  GROUP BY icu_flag, los_quartile
)
SELECT 
  icu_flag,
  los_quartile,
  mortality_rate * 100 AS mortality_pct,
  (mortality_rate - FIRST_VALUE(mortality_rate) OVER w) * 100 AS absolute_diff_vs_q1,
  (mortality_rate - FIRST_VALUE(mortality_rate) OVER w) / NULLIF(FIRST_VALUE(mortality_rate) OVER w, 0) * 100 AS relative_diff_vs_q1,
  mech_vent_pct * 100 AS mech_vent_pct,
  vasopressor_pct * 100 AS vasopressor_pct,
  rrt_pct * 100 AS rrt_pct
FROM quartile_stats
WINDOW w AS (PARTITION BY icu_flag ORDER BY los_quartile)
ORDER BY icu_flag DESC, los_quartile;