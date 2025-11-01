WITH hemorrhagic_cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) BETWEEN 70 AND 80
    AND (
          dd.long_title LIKE '%hemorrhagic%'        -- ICD-10 style description
          OR di.icd_code IN ('430','431','432','I60','I61','I62')  -- ICD-9/ICD-10 codes for hemorrhagic stroke
        )
),
cohort_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hemorrhagic_cohort hc ON hc.hadm_id = a.hadm_id
),
lab_instability AS (
  -- instability score per admission: count of abnormal labs in first 48 hours
  SELECT ca.hadm_id,
         COALESCE(SUM(
           CASE
             WHEN le.valuenum IS NOT NULL
              AND le.charttime >= ca.admittime
              AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
              AND (
                    (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                    OR
                    (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
                  )
           THEN 1 ELSE 0 END
         ), 0) AS instability_score
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ca.hadm_id
   AND le.charttime >= ca.admittime
   AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
   AND le.valuenum IS NOT NULL
  GROUP BY ca.hadm_id
),
critical_events_per_hadm AS (
  -- critical lab events per admission (all admissions in hosp)
  SELECT hadm_id,
         SUM(CASE WHEN LOWER(flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS critical_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
cohort_summary AS (
  SELECT
      COUNT(DISTINCT ca.hadm_id) AS n_admissions_cohort,
      SUM(COALESCE(ce.critical_events, 0)) AS total_critical_events_cohort,
      AVG(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, SECOND) / 86400.0) AS mean_los_cohort,
      AVG(CASE WHEN ca.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_cohort
  FROM cohort_admissions ca
  LEFT JOIN critical_events_per_hadm ce ON ce.hadm_id = ca.hadm_id
),
general_summary AS (
  SELECT
      COUNT(DISTINCT a.hadm_id) AS n_admissions_general,
      SUM(COALESCE(ce.critical_events, 0)) AS total_critical_events_general,
      AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_los_general,
      AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_general
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN critical_events_per_hadm ce ON ce.hadm_id = a.hadm_id
)

-- Part 1: 25th percentile of first-48-hour laboratory instability score for the specified cohort
, instability_percentile AS (
  SELECT
     (SELECT quantiles[OFFSET(24)]
      FROM (
        SELECT APPROX_QUANTILES(i.instability_score, 100) AS quantiles
        FROM lab_instability i
      )
     ) AS instability_25th
  FROM lab_instability
  LIMIT 1
)

-- Part 2: cohort vs general inpatient critical-lab event rate, plus mean LOS and in-hospital mortality
SELECT
  'instability_25th_percentile' AS metric,
  CAST(ip.instability_25th AS FLOAT64) AS value,
  NULL AS n_admissions_cohort,
  NULL AS n_admissions_general,
  NULL AS mean_los_cohort,
  NULL AS mean_los_general,
  NULL AS mortality_cohort,
  NULL AS mortality_general
FROM instability_percentile ip

UNION ALL

SELECT
  'cohort_vs_general' AS metric,
  NULL AS value,
  cs.n_admissions_cohort AS cohort_n_admissions,
  gs.n_admissions_general AS general_n_admissions,
  cs.mean_los_cohort AS cohort_mean_los_days,
  gs.mean_los_general AS general_mean_los_days,
  cs.mortality_cohort AS cohort_in_hospital_mortality,
  gs.mortality_general AS general_in_hospital_mortality
FROM cohort_summary cs
CROSS JOIN general_summary gs;