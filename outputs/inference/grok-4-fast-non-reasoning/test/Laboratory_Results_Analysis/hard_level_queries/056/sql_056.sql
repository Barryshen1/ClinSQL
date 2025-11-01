WITH asthma_cohort AS (
  -- Female patients aged 55-65 with asthma exacerbation
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND (d.icd_code LIKE 'J45%' OR d.icd_code = 'J46')  -- Asthma: J45.*, J46
    AND d.icd_version = 10
),

lab_scores_asthma AS (
  -- Calculate instability score for asthma cohort (first 48h): count of abnormal labs
  SELECT 
    ac.hadm_id,
    COUNT(
      CASE 
        WHEN le.valuenum IS NOT NULL 
             AND (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
             AND (
               (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
               OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL)
             )
        THEN 1
      END
    ) AS instability_score
  FROM asthma_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON ac.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = li.itemid
  WHERE le.charttime >= ac.admittime
    AND le.charttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND li.category IN ('Chemistry', 'Blood Gases', 'Hematology')  -- Key instability labs
    AND le.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
                      WHERE label LIKE '%Sodium%' OR label LIKE '%Potassium%' OR label LIKE '%Chloride%' 
                         OR label LIKE '%Bicarbonate%' OR label LIKE '%BUN%' OR label LIKE '%Creatinine%' 
                         OR label LIKE '%pH%' OR label LIKE '%pCO2%' OR label LIKE '%WBC%' 
                         OR label LIKE '%Eosinophil%')
  GROUP BY ac.hadm_id
),

general_inpatients AS (
  -- All general inpatients for comparison
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

lab_scores_general AS (
  -- Instability score for general cohort (first 48h)
  SELECT 
    gi.hadm_id,
    COUNT(
      CASE 
        WHEN le.valuenum IS NOT NULL 
             AND (le.ref_range_lower IS NOT NULL OR le.ref_range_upper IS NOT NULL)
             AND (
               (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
               OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL)
             )
        THEN 1
      END
    ) AS instability_score
  FROM general_inpatients gi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON gi.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = li.itemid
  WHERE le.charttime >= gi.admittime
    AND le.charttime <= TIMESTAMP_ADD(gi.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND li.category IN ('Chemistry', 'Blood Gases', 'Hematology')
    AND le.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
                      WHERE label LIKE '%Sodium%' OR label LIKE '%Potassium%' OR label LIKE '%Chloride%' 
                         OR label LIKE '%Bicarbonate%' OR label LIKE '%BUN%' OR label LIKE '%Creatinine%' 
                         OR label LIKE '%pH%' OR label LIKE '%pCO2%' OR label LIKE '%WBC%' 
                         OR label LIKE '%Eosinophil%')
  GROUP BY gi.hadm_id
),

top_tier AS (
  -- Top tier: Asthma cohort with score >= 95th percentile
  SELECT 
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    COALESCE(ls.instability_score, 0) AS score
  FROM asthma_cohort ac
  LEFT JOIN lab_scores_asthma ls ON ac.hadm_id = ls.hadm_id
  WHERE COALESCE(ls.instability_score, 0) >= (
    SELECT PERCENTILE_CONT(instability_score, 0.95) 
    FROM lab_scores_asthma
  )
),

general_critical AS (
  -- General inpatients exceeding the asthma 95th threshold
  SELECT 
    gi.hadm_id,
    gi.admittime,
    gi.dischtime,
    gi.hospital_expire_flag,
    COALESCE(ls.instability_score, 0) AS score
  FROM general_inpatients gi
  LEFT JOIN lab_scores_general ls ON gi.hadm_id = ls.hadm_id
  WHERE COALESCE(ls.instability_score, 0) >= (
    SELECT PERCENTILE_CONT(instability_score, 0.95) 
    FROM lab_scores_asthma
  )
)

-- Final outcomes
SELECT 
  'Top Tier (Asthma Females 55-65)' AS cohort,
  COUNT(*) AS n_patients,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate,
  1.0 AS critical_lab_rate  -- 100% by definition
FROM top_tier

UNION ALL

SELECT 
  'General Inpatients' AS cohort,
  COUNT(*) AS n_patients,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate,
  (SELECT COUNT(*) FROM general_critical) * 1.0 / (SELECT COUNT(*) FROM general_inpatients) AS critical_lab_rate
FROM general_inpatients;