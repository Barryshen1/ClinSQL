WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
),
acs_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code IN ('I200','I210','I211','I212','I213','I214','I219','I220','I221','I222','I228','I229') THEN 1 ELSE 0 END) AS has_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
complications AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code IN ('I501','I502','I503','I504','I509','I490','I491','I492','I493','I494','I495','I498','I499') THEN 1 ELSE 0 END) AS has_cardiac_complication,
    MAX(CASE WHEN icd_code IN ('I630','I631','I632','I633','I634','I635','I636','I638','I639','I64','G450','G451','G452','G453','G454','G458','G459') THEN 1 ELSE 0 END) AS has_neurologic_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    b.*,
    COALESCE(af.has_acs, 0) AS has_acs,
    COALESCE(c.has_cardiac_complication, 0) AS has_cardiac_complication,
    COALESCE(c.has_neurologic_complication, 0) AS has_neurologic_complication,
    CASE 
      WHEN b.hospital_expire_flag = 1 AND DATE_DIFF(b.dischtime, b.admittime, DAY) <= 30 THEN 1
      WHEN b.hospital_expire_flag = 0 AND b.dod IS NOT NULL AND DATE_DIFF(CAST(b.dod AS DATETIME), b.admittime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS mortality_30d,
    TIMESTAMP_DIFF(b.dischtime, b.admittime, HOUR) / 24.0 AS hospital_los
  FROM base_cohort b
  LEFT JOIN acs_flag af ON b.hadm_id = af.hadm_id
  LEFT JOIN complications c ON b.hadm_id = c.hadm_id
)
SELECT 
  CASE WHEN has_acs = 1 THEN 'index' ELSE 'control' END AS group_type,
  NULL AS mean_risk_score,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(has_cardiac_complication) AS cardiac_complication_rate,
  AVG(has_neurologic_complication) AS neurologic_complication_rate,
  AVG(CASE WHEN mortality_30d = 0 THEN hospital_los END) AS survivor_mean_los,
  NULL AS matched_profile_percentile
FROM combined
WHERE (has_acs = 1 OR has_acs = 0)
GROUP BY group_type;