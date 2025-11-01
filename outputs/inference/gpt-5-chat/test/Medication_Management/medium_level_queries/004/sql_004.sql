WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),
dx_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
            OR (d.icd_version = 9 AND d.icd_code LIKE '250%' 
                AND SUBSTR(d.icd_code,5,1) IN ('0','2'))
          THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
            OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
          THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_flags f
    ON c.subject_id = f.subject_id
   AND c.hadm_id = f.hadm_id
  WHERE f.has_t2dm = 1
    AND f.has_hf = 1
),
glp1_meds AS (
  SELECT
    hadm_id,
    MIN(starttime) AS first_starttime,
    MAX(stoptime) AS last_stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
  GROUP BY hadm_id
),
metrics AS (
  SELECT
    cd.hadm_id,
    -- started within 72h after admission
    CASE WHEN g.first_starttime IS NOT NULL
              AND g.first_starttime <= cd.admittime + INTERVAL 72 HOUR
         THEN 1 ELSE 0 END AS started_within_72h,
    -- on in last 48h before discharge
    CASE WHEN g.last_stoptime IS NOT NULL
              AND g.last_stoptime >= cd.dischtime - INTERVAL 48 HOUR
         THEN 1 ELSE 0 END AS on_in_last_48h
  FROM cohort_with_dx cd
  LEFT JOIN glp1_meds g
    ON cd.hadm_id = g.hadm_id
)
SELECT
  COUNT(*) AS total_admissions,
  100.0 * SUM(started_within_72h) / COUNT(*) AS pct_started_within_72h,
  100.0 * SUM(on_in_last_48h) / COUNT(*) AS pct_on_in_last_48h,
  (100.0 * SUM(on_in_last_48h) / COUNT(*))
     - (100.0 * SUM(started_within_72h) / COUNT(*)) AS net_change_pct
FROM metrics;