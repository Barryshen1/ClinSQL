WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 44
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND (s.curr_service = 'SURG' OR s.prev_service = 'SURG')
    )
),

charlson_conditions AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '440%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I70%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '43%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '290%') OR (d.icd_version = 10 AND d.icd_code LIKE 'F0%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '490%') OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '710%') OR (d.icd_version = 10 AND d.icd_code LIKE 'M05%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '534%') OR (d.icd_version = 10 AND d.icd_code LIKE 'K25%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '570%') OR (d.icd_version = 10 AND d.icd_code LIKE 'K70%') THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') AND d.icd_code NOT LIKE '250.4%' THEN 1
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.4%') OR (d.icd_version = 10 AND d.icd_code LIKE 'E10.4%') THEN 2
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '342%') OR (d.icd_version = 10 AND d.icd_code LIKE 'G81%') THEN 2
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') THEN 2
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '140%') OR (d.icd_version = 10 AND d.icd_code LIKE 'C0%') THEN 2
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '571%') OR (d.icd_version = 10 AND d.icd_code LIKE 'K71%') THEN 3
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '196%') OR (d.icd_version = 10 AND d.icd_code LIKE 'C77%') THEN 6
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '042%') OR (d.icd_version = 10 AND d.icd_code LIKE 'B20%') THEN 6
      ELSE 0
    END AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
),

charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(weight) AS charlson_score
  FROM charlson_conditions
  GROUP BY subject_id, hadm_id
),

mechvent_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%ventilator%' OR label LIKE '%mechanical ventilation%'
),

mechvent_flags AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM mechvent_items) THEN 1 ELSE 0 END) AS mechvent_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY subject_id, hadm_id
),

vasopressor_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%norepinephrine%' OR label LIKE '%vasopressin%' OR label LIKE '%epinephrine%'
),

vasopressor_flags AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM vasopressor_items) THEN 1 ELSE 0 END) AS vasopressor_flag
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  GROUP BY subject_id, hadm_id
),

rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%dialysis%' OR label LIKE '%RRT%'
),

rrt_flags AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM rrt_items) THEN 1 ELSE 0 END) AS rrt_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY subject_id, hadm_id
),

base_data AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.icu_status,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    COALESCE(cs.charlson_score, 0) AS charlson_score,
    c.hospital_expire_flag,
    COALESCE(mv.mechvent_flag, 0) AS mechvent_flag,
    COALESCE(vp.vasopressor_flag, 0) AS vasopressor_flag,
    COALESCE(rr.rrt_flag, 0) AS rrt_flag
  FROM cohort c
  LEFT JOIN charlson_scores cs ON c.subject_id = cs.subject_id AND c.hadm_id = cs.hadm_id
  LEFT JOIN mechvent_flags mv ON c.subject_id = mv.subject_id AND c.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_flags vp ON c.subject_id = vp.subject_id AND c.hadm_id = vp.hadm_id
  LEFT JOIN rrt_flags rr ON c.subject_id = rr.subject_id AND c.hadm_id = rr.hadm_id
),

categorized AS (
  SELECT
    subject_id,
    hadm_id,
    icu_status,
    CASE
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_category,
    CASE
      WHEN charlson_score <= 3 THEN '≤3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category,
    hospital_expire_flag,
    mechvent_flag,
    vasopressor_flag,
    rrt_flag
  FROM base_data
),

reference_mortality AS (
  SELECT
    icu_status,
    charlson_category,
    AVG(hospital_expire_flag) AS ref_mortality
  FROM categorized
  WHERE los_category = '≤3'
  GROUP BY icu_status, charlson_category
),

grouped AS (
  SELECT
    icu_status,
    los_category,
    charlson_category,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths,
    SUM(mechvent_flag) AS mechvent,
    SUM(vasopressor_flag) AS vasopressors,
    SUM(rrt_flag) AS rrt
  FROM categorized
  GROUP BY icu_status, los_category, charlson_category
)

SELECT
  g.icu_status,
  g.los_category,
  g.charlson_category,
  (g.deaths * 100.0 / g.total) AS mortality_pct,
  (g.deaths * 100.0 / g.total) - (r.ref_mortality * 100.0) AS abs_diff,
  CASE WHEN r.ref_mortality = 0 THEN NULL
       ELSE ((g.deaths * 100.0 / g.total) - (r.ref_mortality * 100.0)) / (r.ref_mortality * 100.0) * 100.0
  END AS rel_diff,
  (g.mechvent * 100.0 / g.total) AS mechvent_pct,
  (g.vasopressors * 100.0 / g.total) AS vasopressors_pct,
  (g.rrt * 100.0 / g.total) AS rrt_pct
FROM grouped g
LEFT JOIN reference_mortality r ON g.icu_status = r.icu_status AND g.charlson_category = r.charlson_category
ORDER BY g.icu_status, g.los_category, g.charlson_category;