WITH age_cohort AS (
  SELECT 
    icustays.stay_id,
    icustays.subject_id,
    icustays.hadm_id,
    icustays.intime,
    icustays.outtime,
    patients.gender,
    patients.anchor_age,
    patients.anchor_year,
    (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 83 AND 93
),

asthma_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '493%')
     OR (icd_version = 10 AND icd_code LIKE 'J45%')
),

cohort AS (
  SELECT 
    age_cohort.*,
    CASE WHEN asthma_patients.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_asthma
  FROM age_cohort
  LEFT JOIN asthma_patients
    ON age_cohort.subject_id = asthma_patients.subject_id
),

qsofa_calc AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN rr.itemid = 220210 THEN rr.valuenum ELSE NULL END) AS max_rr,
    MIN(CASE WHEN sbp.itemid = 220050 THEN sbp.valuenum ELSE NULL END) AS min_sbp,
    MIN(CASE WHEN gcs.itemid = 223900 THEN gcs.valuenum ELSE NULL END) AS min_gcs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` rr
    ON c.stay_id = rr.stay_id
    AND rr.itemid = 220210
    AND rr.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` sbp
    ON c.stay_id = sbp.stay_id
    AND sbp.itemid = 220050
    AND sbp.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` gcs
    ON c.stay_id = gcs.stay_id
    AND gcs.itemid = 223900
    AND gcs.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),

qsofa_scores AS (
  SELECT 
    c.stay_id,
    c.has_asthma,
    (CASE WHEN max_rr >= 22 THEN 1 ELSE 0 END +
     CASE WHEN min_sbp <= 100 THEN 1 ELSE 0 END +
     CASE WHEN min_gcs < 15 THEN 1 ELSE 0 END) AS qsofa_score,
    c.los AS icu_los,
    a.hospital_expire_flag
  FROM cohort c
  LEFT JOIN qsofa_calc q
    ON c.stay_id = q.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
)

SELECT 
  'asthma' AS group_name,
  STDDEV(qsofa_score) AS std_dev,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qsofa_score) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qsofa_score) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qsofa_score) AS p75,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY qsofa_score) AS p95,
  AVG(qsofa_score) AS avg_score,
  AVG(icu_los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM qsofa_scores
WHERE has_asthma = 1

UNION ALL

SELECT 
  'non_asthma' AS group_name,
  STDDEV(qsofa_score) AS std_dev,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY qsofa_score) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qsofa_score) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qsofa_score) AS p75,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY qsofa_score) AS p95,
  AVG(qsofa_score) AS avg_score,
  AVG(icu_los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM qsofa_scores
WHERE has_asthma = 0;