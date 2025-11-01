WITH ami_inpatients AS (
  SELECT DISTINCT a.subject_id,
                  a.hadm_id,
                  a.admittime,
                  a.dischtime,
                  a.deathtime,
                  a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dic
    ON dic.subject_id = a.subject_id AND dic.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      (dic.icd_version = 10 AND dic.icd_code LIKE 'I21%') OR
      (dic.icd_version = 9  AND dic.icd_code LIKE '410%')
    )
),

lab72 AS (
  -- labs in the first 72 hours after admission for AMI inpatients
  SELECT a.hadm_id, l.charttime, l.valuenum
  FROM ami_inpatients AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE l.valuenum IS NOT NULL
),

instability AS (
  -- per-hadm LIS: standard deviation of lab values in first 72h
  SELECT hadm_id, STDDEV_POP(valuenum) AS instability_score
  FROM lab72
  GROUP BY hadm_id
),

instab_p75 AS (
  -- 75th percentile LIS across the AMI cohort
  SELECT quantiles[OFFSET(74)] AS p75_lab_instability
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
    FROM instability
    WHERE instability_score IS NOT NULL
  ) t
),

ami_critical AS (
  -- count of critical labs (within 72h) for AMI inpatients
  SELECT a.hadm_id,
         SUM(CASE WHEN REGEXP_CONTAINS(LOWER(IFNULL(l.flag, '')), r'critical') THEN 1 ELSE 0 END) AS critical_count
  FROM ami_inpatients AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

critical_all AS (
  -- count of critical labs for all admissions (general inpatients)
  SELECT a.hadm_id,
         SUM(CASE WHEN REGEXP_CONTAINS(LOWER(IFNULL(l.flag, '')), r'critical') THEN 1 ELSE 0 END) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

ami_crit_rate AS (
  SELECT AVG(CASE WHEN critical_count > 0 THEN 1 ELSE 0 END) AS ami_crit_rate
  FROM ami_critical
),

general_crit_rate AS (
  SELECT AVG(CASE WHEN critical_count > 0 THEN 1 ELSE 0 END) AS general_crit_rate
  FROM critical_all
),

ami_los AS (
  SELECT hadm_id,
         (TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS los_days
  FROM ami_inpatients
  WHERE dischtime IS NOT NULL
),

los_summary AS (
  SELECT AVG(los_days) AS avg_los_days,
         (SELECT quant[OFFSET(49)]
          FROM (
            SELECT APPROX_QUANTILES(los_days, 100) AS quant
            FROM ami_los
          )
         ) AS median_los_days
  FROM ami_los
),

mortality AS (
  SELECT AVG(CASE WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM ami_inpatients
)

SELECT
  -- 75th percentile LIS for the AMI cohort
  (SELECT p75_lab_instability FROM instab_p75) AS p75_lab_instability_ami,
  -- critical lab frequency in AMI cohort vs general inpatients
  (SELECT ami_crit_rate FROM ami_crit_rate) AS ami_critical_rate,
  (SELECT general_crit_rate FROM general_crit_rate) AS general_inpatient_critical_rate,
  -- LOS and mortality for the AMI cohort
  (SELECT avg_los_days FROM los_summary) AS avg_los_days,
  (SELECT median_los_days FROM los_summary) AS median_los_days,
  (SELECT mortality_rate FROM mortality) AS mortality_rate;