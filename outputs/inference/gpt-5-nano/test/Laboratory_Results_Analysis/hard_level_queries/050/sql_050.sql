WITH ARDS_COHORT AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(dd.long_title) LIKE '%ards%'
),

-- 2) Compute LIS (laboratory-instability score) per admission for ARDS cohort
LIS_PER_ADM AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         SUM(
           CASE 
             WHEN l.ref_range_lower IS NOT NULL
              AND l.ref_range_upper IS NOT NULL
              AND l.valuenum IS NOT NULL
              AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
             THEN 1
             ELSE 0
           END
         ) AS lis_72h
  FROM ARDS_COHORT AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.subject_id = a.subject_id
   AND l.charttime >= a.admittime
   AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- 3) 75th percentile LIS within ARDS cohort
P75 AS (
  SELECT quantiles[OFFSET(74)] AS lis_p75
  FROM (
    SELECT APPROX_QUANTILES(lis_72h, 100) AS quantiles
    FROM LIS_PER_ADM
  )
),

-- 4) Admissions in ARDS cohort with LIS >= P75 (threshold group)
ARDS_THRESHOLD AS (
  SELECT lisadm.subject_id, lisadm.hadm_id, lisadm.admittime, lisadm.dischtime, lisadm.hospital_expire_flag, lisadm.lis_72h
  FROM LIS_PER_ADM lisadm
  CROSS JOIN P75 p
  WHERE lisadm.lis_72h >= p.lis_p75
),

-- 5) Non-ARDS age-matched female controls (same age window, but no ARDS)
NONARDS_COHORT AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 40 AND 50
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%ards%'
    )
),

LIS_PER_ADM_NONARDS AS (
  SELECT n.subject_id, n.hadm_id, n.admittime, n.dischtime, n.hospital_expire_flag,
         SUM(
           CASE 
             WHEN l.ref_range_lower IS NOT NULL
              AND l.ref_range_upper IS NOT NULL
              AND l.valuenum IS NOT NULL
              AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
             THEN 1
             ELSE 0
           END
         ) AS lis_72h
  FROM NONARDS_COHORT AS n
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = n.hadm_id
   AND l.subject_id = n.subject_id
   AND l.charttime >= n.admittime
   AND l.charttime < TIMESTAMP_ADD(n.admittime, INTERVAL 72 HOUR)
  GROUP BY n.subject_id, n.hadm_id, n.admittime, n.dischtime, n.hospital_expire_flag
)

-- 6) Final output: ARDS threshold statistics and non-ARDS age-matched statistics
SELECT
  lis75.lis_p75 AS lis_75th_percentile_of_ARDSLIS,

  -- Threshold ARDS group outcomes
  (SELECT AVG(hospital_expire_flag) FROM ARDS_THRESHOLD) AS thresh_mortality_rate,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND)/3600.0) FROM ARDS_THRESHOLD) AS thresh_mean_los_hours,

  -- Threshold ARDS: average critical lab events per patient (per-patient average LIS within threshold admissions)
  (SELECT AVG(avg_lis_per_adm) FROM (
     SELECT subject_id, AVG(lis_72h) AS avg_lis_per_adm
     FROM LIS_PER_ADM
     WHERE hadm_id IN (SELECT hadm_id FROM ARDS_THRESHOLD)
     GROUP BY subject_id
  )) AS thresh_avg_critical_lab_events_per_patient,

  -- Non-ARDS age-matched controls: average critical lab events per patient
  (SELECT AVG(avg_lis_per_adm) FROM (
     SELECT subject_id, AVG(lis_72h) AS avg_lis_per_adm
     FROM LIS_PER_ADM_NONARDS
     GROUP BY subject_id
  )) AS nonards_avg_critical_lab_events_per_patient,

  -- Optional: difference in per-patient LIS between threshold ARDS and non-ARDS controls
  (
    SELECT AVG(avg_lis_per_adm) FROM (
      SELECT subject_id, AVG(lis_72h) AS avg_lis_per_adm
      FROM LIS_PER_ADM
      WHERE hadm_id IN (SELECT hadm_id FROM ARDS_THRESHOLD)
      GROUP BY subject_id
    )
  ) -
  (
    SELECT AVG(avg_lis_per_adm) FROM (
      SELECT subject_id, AVG(lis_72h) AS avg_lis_per_adm
      FROM LIS_PER_ADM_NONARDS
      GROUP BY subject_id
    )
  ) AS diff_threshold_vs_nonards
FROM P75 lis75;