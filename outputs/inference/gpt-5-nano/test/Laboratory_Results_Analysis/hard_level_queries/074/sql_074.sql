WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- age at admission using anchor_age/year
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
subgroup AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag,
    b.age_at_admit,
    (TIMESTAMP_DIFF(b.dischtime, b.admittime, SECOND) / 3600.0) AS los_hours
  FROM base AS b
),
lab_instab AS (
  SELECT
    s.hadm_id,
    COUNT(DISTINCT l.itemid) AS lab_instability_score
  FROM subgroup s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = s.subject_id
   AND l.hadm_id = s.hadm_id
  WHERE l.charttime >= s.admittime
    AND l.charttime <= TIMESTAMP_ADD(s.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (
      (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
      OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
      OR LOWER(IFNULL(l.flag, '')) IN ('h','high','critical')
      OR LOWER(IFNULL(l.flag, '')) IN ('l','low')
    )
  GROUP BY s.hadm_id
),
instab_all AS (
  SELECT s.hadm_id,
         COALESCE(li.lab_instability_score, 0) AS lab_instability_score
  FROM subgroup s
  LEFT JOIN lab_instab li ON s.hadm_id = li.hadm_id
),
metrics AS (
  SELECT
    -- maximum instability score in subgroup
    (SELECT COALESCE(MAX(lab_instability_score), 0) FROM instab_all) AS max_lab_instability_score_subgroup,
    -- average LOS for subgroup
    (SELECT AVG(los_hours) FROM subgroup) AS los_subgroup,
    -- deaths and admissions in subgroup
    (SELECT SUM(CASE WHEN (deathtime IS NOT NULL OR hospital_expire_flag = 1) THEN 1 ELSE 0 END)
     FROM subgroup) AS deaths_subgroup,
    (SELECT COUNT(*) FROM subgroup) AS admissions_subgroup,
    -- general inpatients LOS
    (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600.0)
     FROM `physionet-data.mimiciv_3_1_hosp.admissions`
     WHERE dischtime IS NOT NULL) AS los_general,
    -- general deaths
    (SELECT SUM(CASE WHEN (deathtime IS NOT NULL OR hospital_expire_flag = 1) THEN 1 ELSE 0 END)
     FROM `physionet-data.mimiciv_3_1_hosp.admissions`
     WHERE dischtime IS NOT NULL) AS deaths_general,
    -- general admissions
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE dischtime IS NOT NULL) AS admissions_general
)
SELECT
  max_lab_instability_score_subgroup,
  (deaths_subgroup * 1.0) / admissions_subgroup AS critical_event_rate_subgroup,
  (deaths_general * 1.0) / admissions_general AS critical_event_rate_general,
  los_subgroup,
  (deaths_subgroup * 1.0) / admissions_subgroup AS mortality_subgroup,
  los_general,
  (deaths_general * 1.0) / admissions_general AS mortality_general
FROM metrics;