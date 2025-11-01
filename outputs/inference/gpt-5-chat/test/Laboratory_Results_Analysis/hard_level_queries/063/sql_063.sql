WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
         pat.gender, pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
    AND (
      (dx.icd_version = 9  AND dx.icd_code LIKE '4151%')
      OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
    )
),
lab_scores AS (
  SELECT c.subject_id, c.hadm_id,
         COUNTIF(flag IS NOT NULL) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id = le.hadm_id
   AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
p75_threshold AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM lab_scores
),
subset_ge_p75 AS (
  SELECT ls.subject_id, ls.hadm_id, ls.instability_score, adm.hospital_expire_flag,
         DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM lab_scores ls
  JOIN p75_threshold p
    ON TRUE
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ls.subject_id = adm.subject_id AND ls.hadm_id = adm.hadm_id
  WHERE ls.instability_score >= p.p75_score
),
critical_rate_subset AS (
  SELECT COUNTIF(LOWER(flag) = 'critical') / COUNT(*) AS crit_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN subset_ge_p75 s
    ON le.subject_id = s.subject_id AND le.hadm_id = s.hadm_id
),
critical_rate_all_inpatients AS (
  SELECT COUNTIF(LOWER(flag) = 'critical') / COUNT(*) AS crit_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE hadm_id IS NOT NULL
),
mortality_los AS (
  SELECT 
    100.0 * COUNTIF(hospital_expire_flag = 1) / COUNT(*) AS mortality_pct,
    AVG(los_days) AS mean_los_days
  FROM subset_ge_p75
)
SELECT p.p75_score,
       m.mortality_pct,
       m.mean_los_days,
       crs.crit_rate AS critical_lab_rate_subset,
       cra.crit_rate AS critical_lab_rate_all_inpatients
FROM p75_threshold p
CROSS JOIN mortality_los m
CROSS JOIN critical_rate_subset crs
CROSS JOIN critical_rate_all_inpatients cra;