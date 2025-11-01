WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 65 AND 75
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN (
          'K5701', 'K5711', 'K5721', 'K5731', 
          'K5741', 'K5751', 'K5781', 'K5791',
          'K625', 'K635'
        )
    )
),
cohort_lab_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY c.hadm_id
),
general_lab_scores AS (
  SELECT 
    a.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  WHERE l.charttime >= a.admittime
    AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY a.hadm_id
),
cohort_los_mort AS (
  SELECT 
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / (24 * 3600) AS los_days,
    c.hospital_expire_flag AS mortality
  FROM cohort c
)
SELECT 
  (SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(25)] 
   FROM cohort_lab_scores) AS cohort_25th_percentile,
  (SELECT AVG(lab_instability_score) FROM cohort_lab_scores) AS cohort_avg_critical_lab_freq,
  (SELECT AVG(lab_instability_score) FROM general_lab_scores) AS general_avg_critical_lab_freq,
  (SELECT AVG(los_days) FROM cohort_los_mort) AS cohort_avg_los,
  (SELECT AVG(mortality) FROM cohort_los_mort) AS cohort_mortality_rate;