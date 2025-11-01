WITH sepsis_cohort AS (
  -- Define female admissions aged 43-53 with sepsis (ICD-10 A41*)
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXTRACT(YEAR FROM p.anchor_year) >= 2008  -- Ensure adult anchor age validity
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'A41%'
    AND a.hadm_id IS NOT NULL
    AND a.admittime < a.dischtime  -- Valid admission
),

critical_labs AS (
  -- Count abnormal labs (flag='A') in first 72h for cohort
  SELECT 
    sc.hadm_id,
    COUNT(*) AS critical_event_count
  FROM sepsis_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sc.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.charttime >= sc.admittime
    AND l.charttime < TIMESTAMP_ADD(sc.admittime, INTERVAL 3 DAY)
    AND l.flag = 'A'  -- Abnormal flag (string)
    AND li.category IN ('Blood Gases', 'Chemistry', 'Hematology', 'Coagulation')
    AND l.valuenum IS NOT NULL  -- Valid numeric value
    AND l.specimen_id IS NOT NULL  -- Actual lab specimen
  GROUP BY sc.hadm_id
),

all_admissions_with_scores AS (
  -- All cohort admissions, with critical count (0 if no labs)
  SELECT 
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag,
    COALESCE(cl.critical_event_count, 0) AS critical_event_count
  FROM sepsis_cohort sc
  LEFT JOIN critical_labs cl
    ON sc.hadm_id = cl.hadm_id
)

-- Final aggregates
SELECT 
  COUNT(DISTINCT hadm_id) AS cohort_size,
  PERCENTILE_CONT(critical_event_count, 0.25) OVER() AS p25_instability_score,
  AVG(critical_event_count) AS mean_critical_events_per_admission,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(hospital_expire_flag * 1.0) AS mortality_rate
FROM all_admissions_with_scores
WHERE dischtime IS NOT NULL;  -- Ensure LOS calculable;