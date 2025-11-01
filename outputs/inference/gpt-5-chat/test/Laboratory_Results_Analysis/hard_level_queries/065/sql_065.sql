WITH
-- Filter females 65–75 with lower GI bleed diagnosis
lgib_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.anchor_age, p.gender,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND (
      (LOWER(dd.long_title) LIKE '%lower%' AND LOWER(dd.long_title) LIKE '%gastro%')
       OR (LOWER(dd.long_title) LIKE '%lower%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
       OR LOWER(dd.long_title) LIKE '%gi bleed%'
       OR (LOWER(dd.long_title) LIKE '%diverticul%' AND LOWER(dd.long_title) LIKE '%hemorrhage%')
    )
),

-- All admissions with lab instability score in first 72h
lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(LOWER(le.flag) = 'abnormal') AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),

-- Combine with LOS/mortality info
admission_scores AS (
  SELECT
    a.subject_id, a.hadm_id,
    ls.lab_instability_score,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN lab_scores ls
    ON a.subject_id = ls.subject_id AND a.hadm_id = ls.hadm_id
)

-- Final outputs
SELECT
  -- 25th percentile lab instability score in target cohort
  (SELECT
     APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(25)]
   FROM admission_scores ads
   JOIN lgib_cohort l
     ON ads.hadm_id = l.hadm_id
  ) AS lab_instability_score_p25,

  -- Compare freq of critical labs between cohort and general inpatients
  (SELECT AVG(lab_instability_score)
   FROM admission_scores ads
   JOIN lgib_cohort l
     ON ads.hadm_id = l.hadm_id
  ) AS avg_abnormal_labs_cohort,

  (SELECT AVG(lab_instability_score)
   FROM admission_scores ads
   WHERE hadm_id NOT IN (SELECT hadm_id FROM lgib_cohort)
  ) AS avg_abnormal_labs_general,

  -- Cohort LOS and mortality
  (SELECT AVG(los_days)
   FROM admission_scores ads
   JOIN lgib_cohort l
     ON ads.hadm_id = l.hadm_id
  ) AS avg_los_days_cohort,

  (SELECT 100.0 * SUM(ads.hospital_expire_flag) / COUNT(*)
   FROM admission_scores ads
   JOIN lgib_cohort l
     ON ads.hadm_id = l.hadm_id
  ) AS mortality_rate_pct_cohort;