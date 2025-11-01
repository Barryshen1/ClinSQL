WITH ami_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410.%')
     OR (icd_version = 10 AND icd_code LIKE 'I21%')
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime, 
    a.hospital_expire_flag,
    a.admission_type,
    p.gender, 
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8' 
    END AS los_group,
    CASE WHEN a.admission_type = 'EMERGENCY' THEN 'Emergent' ELSE 'Non-emergent' END AS adm_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN ami_hadms ah 
    ON a.hadm_id = ah.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
),
decedents AS (
  SELECT 
    los_group, 
    adm_group,
    TIMESTAMP_DIFF(deathtime, admittime, DAY) AS ttd_days
  FROM cohort
  WHERE hospital_expire_flag = 1
),
counts AS (
  SELECT 
    los_group, 
    adm_group,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct
  FROM cohort
  GROUP BY los_group, adm_group
),
medians AS (
  SELECT DISTINCT
    los_group, 
    adm_group,
    PERCENTILE_CONT(ttd_days, 0.5) OVER (PARTITION BY los_group, adm_group) AS median_ttd
  FROM decedents
)
SELECT 
  c.los_group, 
  c.adm_group,
  c.n,
  c.deaths,
  c.mortality_pct,
  COALESCE(m.median_ttd, 0) AS median_ttd_days
FROM counts c
LEFT JOIN medians m 
  ON c.los_group = m.los_group AND c.adm_group = m.adm_group
ORDER BY 
  CASE c.los_group 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    ELSE 3 
  END,
  CASE c.adm_group WHEN 'Emergent' THEN 1 ELSE 2 END;