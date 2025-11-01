WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '427.5%') 
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I46%')
        )
    )
),
med_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pres.drug) AS num_drugs,
    COUNT(DISTINCT CASE 
      WHEN LOWER(COALESCE(pres.drug, '')) LIKE '%morphine%' 
        OR LOWER(pres.drug) LIKE '%fentanyl%' 
        OR LOWER(pres.drug) LIKE '%heparin%' 
        OR LOWER(pres.drug) LIKE '%warfarin%' 
        OR LOWER(pres.drug) LIKE '%insulin%' 
      THEN pres.drug 
    END) AS num_hr,
    COUNT(DISTINCT CASE WHEN pres.route IS NOT NULL AND TRIM(pres.route) != '' THEN pres.route END) AS num_routes
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pres.hadm_id = c.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
    AND pres.drug IS NOT NULL 
    AND TRIM(pres.drug) != ''
  GROUP BY c.hadm_id
),
scores AS (
  SELECT 
    hadm_id,
    COALESCE(num_drugs, 0) + 2 * COALESCE(num_hr, 0) + COALESCE(num_routes, 0) AS score
  FROM med_scores
),
cohort_with_readmit AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    LOGICAL_OR(
      a.admittime > c.dischtime 
      AND a.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      AND a.hadm_id != c.hadm_id
    ) AS has_readmit
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON c.subject_id = a.subject_id
  GROUP BY 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag
),
joined AS (
  SELECT 
    s.hadm_id,
    s.score,
    cwr.admittime,
    cwr.dischtime,
    cwr.hospital_expire_flag,
    cwr.has_readmit,
    NTILE(3) OVER (ORDER BY s.score ASC) AS tertile
  FROM scores s
  JOIN cohort_with_readmit cwr 
    ON s.hadm_id = cwr.hadm_id
)
SELECT 
  tertile,
  COUNT(*) AS counts,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(hospital_expire_flag * 100.0) AS mortality_pct,
  AVG(IF(has_readmit, 100.0, 0.0)) AS readmission_30d_pct
FROM joined
GROUP BY tertile
ORDER BY tertile;