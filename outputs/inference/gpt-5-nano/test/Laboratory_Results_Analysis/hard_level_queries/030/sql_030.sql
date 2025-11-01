WITH asthma_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND d.icd_code LIKE 'J45%'
),

lab_instability_per_adm AS (
  -- Include all asthma admissions; count only labs abnormal within first 48h
  SELECT
    a.hadm_id,
    COUNT(l.valuenum) AS lab_instability_score
  FROM asthma_admissions AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
   AND l.valuenum IS NOT NULL
   AND ((l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) OR
        (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper))
  GROUP BY a.hadm_id
),

critical_events_asthma AS (
  -- Critical-lab events within 48h for asthma admissions
  SELECT
    a.hadm_id,
    COUNT(l.valuenum) AS critical_events
  FROM asthma_admissions AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
   AND l.valuenum IS NOT NULL
   AND ((l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower * 0.5) OR
        (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper * 1.5))
  GROUP BY a.hadm_id
),

critical_events_all AS (
  -- Critical-lab events within 48h for all admissions (inpatients)
  SELECT
    a.hadm_id,
    COUNT(l.valuenum) AS critical_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON l.hadm_id = a.hadm_id
  WHERE l.charttime >= a.admittime
    AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND ((l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower * 0.5) OR
         (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper * 1.5))
  GROUP BY a.hadm_id
)

SELECT
  (SELECT COUNT(*) FROM asthma_admissions) AS asthma_admissions_count,

  -- 75th percentile of lab-instability score in the first 48 hours for asthma cohort
  (
    SELECT quantiles[OFFSET(75)]
    FROM (
      SELECT APPROX_QUANTILES(lab_instability_score, 100) AS quantiles
      FROM lab_instability_per_adm
    )
  ) AS p75_lab_instability_asthma_48h,

  -- Mean number of critical-lab events within 48h per admission: asthma vs all inpatients
  (SELECT AVG(COALESCE(ce.critical_events, 0))
     FROM asthma_admissions aa
     LEFT JOIN critical_events_asthma ce ON aa.hadm_id = ce.hadm_id
  ) AS mean_critical_events_per_adm_48h_asthma,

  (SELECT AVG(COALESCE(ceAll.critical_events, 0))
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
     LEFT JOIN critical_events_all ceAll ON a.hadm_id = ceAll.hadm_id
  ) AS mean_critical_events_per_adm_48h_all_inpatients,

  -- Cohort LOS and in-hospital mortality
  (SELECT AVG(los_days) FROM asthma_admissions) AS mean_los_days_asthma__cohort,
  (SELECT AVG(hospital_expire_flag) FROM asthma_admissions) AS in_hospital_mortality_rate_asthma_cohort;