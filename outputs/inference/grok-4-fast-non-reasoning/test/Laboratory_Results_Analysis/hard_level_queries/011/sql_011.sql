WITH base_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
),

aki_subjects AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  INNER JOIN base_patients bp ON di.subject_id = bp.subject_id
  WHERE (di.icd_version = 'ICD-9' AND di.icd_code LIKE '584.%')
     OR (di.icd_version = 'ICD-10' AND di.icd_code LIKE 'N17%')
),

non_aki_subjects AS (
  SELECT bp.subject_id
  FROM base_patients bp
  LEFT JOIN (
    SELECT DISTINCT di.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE (di.icd_version = 'ICD-9' AND di.icd_code LIKE '584.%')
       OR (di.icd_version = 'ICD-10' AND di.icd_code LIKE 'N17%')
  ) akis ON bp.subject_id = akis.subject_id
  WHERE akis.subject_id IS NULL
),

aki_cohort AS (
  SELECT bp.subject_id, a.hadm_id, a.admittime,
         ROW_NUMBER() OVER (PARTITION BY bp.subject_id ORDER BY a.admittime) AS rn
  FROM base_patients bp
  INNER JOIN aki_subjects akis ON bp.subject_id = akis.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON bp.subject_id = a.subject_id
),

control_cohort AS (
  SELECT nas.subject_id, a.hadm_id, a.admittime,
         ROW_NUMBER() OVER (PARTITION BY nas.subject_id ORDER BY a.admittime) AS rn
  FROM non_aki_subjects nas
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON nas.subject_id = a.subject_id
),

cohorts AS (
  SELECT subject_id, hadm_id, admittime, 'AKI' AS group_label 
  FROM aki_cohort 
  WHERE rn = 1
  UNION ALL
  SELECT subject_id, hadm_id, admittime, 'Control' AS group_label 
  FROM control_cohort 
  WHERE rn = 1
),

scr_instability AS (
  SELECT c.subject_id, c.hadm_id, c.group_label,
         COALESCE(
           MAX(CASE WHEN le.itemid = 50912 AND le.charttime BETWEEN c.admittime AND c.admittime + INTERVAL 3 DAY 
                    THEN le.valuenum END) -
           MIN(CASE WHEN le.itemid = 50912 AND le.charttime BETWEEN c.admittime AND c.admittime + INTERVAL 3 DAY 
                    THEN le.valuenum END), CAST(0 AS FLOAT64)
         ) AS instability_score
  FROM cohorts c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  WHERE le.itemid = 50912  -- Serum Creatinine
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
  GROUP BY c.subject_id, c.hadm_id, c.group_label
  HAVING COUNT(le.valuenum) >= 2  -- At least 2 measurements
),

critical_events AS (
  SELECT c.subject_id, c.hadm_id, c.group_label,
         COUNT(CASE WHEN ce.itemid IN (220045, 211, 220179, 618, 220277, 676) 
                    AND ce.valuenum IS NOT NULL
                    AND ce.charttime >= i.intime
                    AND ce.charttime <= i.intime + INTERVAL 1 DAY
                    AND (
                      (ce.itemid IN (220045, 211) AND (ce.valuenum < 50 OR ce.valuenum > 130)) OR  -- HR
                      (ce.itemid = 220179 AND ce.valuenum < 90) OR  -- SBP
                      (ce.itemid = 618 AND ce.valuenum > 35) OR  -- RR
                      (ce.itemid = 220277 AND ce.valuenum < 90) OR  -- SpO2
                      (ce.itemid = 676 AND (ce.valuenum > 39 OR ce.valuenum < 35))  -- Temp
                    )
               THEN 1 END) AS crit_event_count
  FROM cohorts c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.subject_id = ce.subject_id AND i.stay_id = ce.stay_id
  GROUP BY c.subject_id, c.hadm_id, c.group_label
),

los_calc AS (
  SELECT c.subject_id, c.hadm_id, c.group_label,
         SUM(TIMESTAMP_DIFF(t.outtime, t.intime, HOUR) / 24.0) AS los_days
  FROM cohorts c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  WHERE t.intime IS NOT NULL AND t.outtime IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.group_label
),

mortality AS (
  SELECT c.subject_id, c.hadm_id, c.group_label,
         a.hospital_expire_flag
  FROM cohorts c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
)

-- Aggregate metrics for both cohorts
SELECT
  cohort,
  ROUND(AVG(instability_score), 2) AS mean_instability_score,
  ROUND(AVG(COALESCE(crit_event_count, 0)), 2) AS mean_critical_events,
  ROUND(AVG(COALESCE(los_days, 0)), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag), 4) AS mean_mortality
FROM (
  SELECT 
    CASE WHEN c.group_label = 'AKI' THEN 'AKI' ELSE 'Control' END AS cohort,
    COALESCE(si.instability_score, CAST(0 AS FLOAT64)) AS instability_score,
    COALESCE(ce.crit_event_count, 0) AS crit_event_count,
    COALESCE(lc.los_days, 0) AS los_days,
    COALESCE(m.hospital_expire_flag, 0) AS hospital_expire_flag
  FROM cohorts c
  LEFT JOIN scr_instability si ON c.subject_id = si.subject_id AND c.hadm_id = si.hadm_id
  LEFT JOIN critical_events ce ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id
  LEFT JOIN los_calc lc ON c.subject_id = lc.subject_id AND c.hadm_id = lc.hadm_id
  LEFT JOIN mortality m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
)
GROUP BY cohort
ORDER BY cohort;