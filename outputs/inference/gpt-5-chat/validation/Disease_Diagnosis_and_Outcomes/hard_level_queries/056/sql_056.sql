WITH patient_base AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT seq_num) AS dx_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
septic_shock_flags AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%septic shock%'
),
drg_info AS (
  SELECT
    hadm_id,
    MAX(CAST(drg_severity AS INT64)) AS drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
general_inpatients AS (
  SELECT
    pb.subject_id,
    pb.hadm_id,
    dc.dx_count,
    di.drg_severity,
    DATETIME_DIFF(pb.dischtime, pb.admittime, DAY) AS los_days,
    CASE
      WHEN (pb.deathtime IS NOT NULL AND DATETIME_DIFF(pb.deathtime, pb.admittime, DAY) <= 90)
        OR (pb.dod IS NOT NULL AND DATETIME_DIFF(pb.dod, pb.admittime, DAY) <= 90)
      THEN 1 ELSE 0
    END AS mort_90d,
    CASE
      WHEN di.drg_severity >= 3 THEN 1 ELSE 0
    END AS major_complication
  FROM patient_base pb
  LEFT JOIN diagnosis_counts dc ON pb.hadm_id = dc.hadm_id
  LEFT JOIN drg_info di ON pb.hadm_id = di.hadm_id
),
cohort AS (
  SELECT g.*
  FROM general_inpatients g
  JOIN `septic_shock_flags` ss ON g.hadm_id = ss.hadm_id
  JOIN patient_base pb ON g.hadm_id = pb.hadm_id
  WHERE pb.gender = 'M'
    AND pb.anchor_age BETWEEN 63 AND 73
    AND g.dx_count > 15
)
SELECT
  -- Cohort stats
  AVG(drg_severity) AS mean_risk_score,
  AVG(mort_90d) AS mort_90d_rate,
  -- Compare complication rate and survivor LOS to general inpatients
  AVG(major_complication) AS major_complication_rate_cohort,
  (SELECT AVG(major_complication) FROM general_inpatients) AS major_complication_rate_general,
  AVG(CASE WHEN mort_90d = 0 THEN los_days END) AS survivor_los_cohort,
  (SELECT AVG(CASE WHEN mort_90d = 0 THEN los_days END) FROM general_inpatients) AS survivor_los_general,
  -- Percentile for profile: 68M, 16 diagnoses
  (SELECT DISTINCT PERCENT_RANK() OVER (ORDER BY los_days)
   FROM general_inpatients gi
   JOIN patient_base pb ON gi.hadm_id = pb.hadm_id
   WHERE pb.gender = 'M' AND pb.anchor_age = 68 AND dx_count = 16
   LIMIT 1) AS los_percentile_profile
FROM cohort;