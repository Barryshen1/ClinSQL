WITH
target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(dd.long_title) LIKE '%hyperosmolar%'
),
lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN target_admissions ta
    ON ta.subject_id = l.subject_id AND ta.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
instability AS (
  SELECT hadm_id, STDDEV_SAMP(valuenum) AS instability_score
  FROM lab_events
  GROUP BY hadm_id
  HAVING COUNT(*) >= 2
),
labstats AS (
  SELECT le.hadm_id,
         COUNT(*) AS total_labs,
         SUM(
           CASE WHEN le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower THEN 1 ELSE 0 END
           +
           CASE WHEN le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END
         ) AS critical_labs
  FROM lab_events le
  GROUP BY le.hadm_id
),
per_admission AS (
  SELECT ta.hadm_id, ta.subject_id,
         a.admittime, a.dischtime, a.hospital_expire_flag,
         i.instability_score,
         ls.total_labs, ls.critical_labs,
         CASE WHEN ls.total_labs > 0 THEN CAST(ls.critical_labs AS FLOAT64) / ls.total_labs ELSE NULL END AS critical_rate
  FROM target_admissions ta
  LEFT JOIN instability i ON i.hadm_id = ta.hadm_id
  LEFT JOIN labstats ls ON ls.hadm_id = ta.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = ta.hadm_id
),
p75 AS (
  SELECT IFNULL(APPROX_QUANTILES(instability_score, 100)[OFFSET(74)], NULL) AS p75_score
  FROM instability
  WHERE instability_score IS NOT NULL
),
threshold_group AS (
  SELECT pa.*
  FROM per_admission pa
  CROSS JOIN p75
  WHERE pa.instability_score >= p75.p75_score
),
general_group AS (
  SELECT pa.*
  FROM per_admission pa
  CROSS JOIN p75
  WHERE pa.instability_score < p75.p75_score
)
SELECT
  p75.p75_score AS instability_75th_percentile,
  (SELECT COUNT(*) FROM threshold_group) AS threshold_admissions,
  (SELECT AVG(hospital_expire_flag) FROM threshold_group) AS threshold_mortality_rate,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND)/86400.0) FROM threshold_group) AS threshold_mean_los_days,
  (SELECT AVG(critical_rate) FROM threshold_group) AS threshold_mean_crit_rate,
  (SELECT AVG(critical_rate) FROM general_group) AS general_mean_crit_rate
FROM p75;