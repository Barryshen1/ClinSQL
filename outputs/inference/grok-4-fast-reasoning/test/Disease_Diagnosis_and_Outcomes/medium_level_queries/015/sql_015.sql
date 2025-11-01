WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_adm,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 48 AND 58
),
stroke_adm AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id
  WHERE ((d.icd_version = '9' AND d.icd_code BETWEEN '430' AND '438')
     OR (d.icd_version = '10' AND d.icd_code LIKE 'I6%'))
    AND d.seq_num = 1
),
cohort_stroke AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN stroke_adm s ON c.hadm_id = s.hadm_id
),
icu_flag AS (
  SELECT 
    cs.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = cs.hadm_id
      ) THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS icu_cat
  FROM cohort_stroke cs
),
comorb AS (
  SELECT 
    adm.hadm_id,
    COUNT(CASE WHEN d.seq_num > 1 THEN 1 END) AS num_comorb
  FROM icu_flag adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON adm.hadm_id = d.hadm_id
  GROUP BY adm.hadm_id
),
final_cohort AS (
  SELECT 
    adm.*,
    co.num_comorb,
    CASE 
      WHEN co.num_comorb <= 2 THEN 'Low'
      WHEN co.num_comorb <= 5 THEN 'Medium'
      ELSE 'High'
    END AS comorb_cat,
    CASE 
      WHEN adm.los_days <= 5 THEN '<=5' 
      ELSE '>5' 
    END AS los_cat
  FROM icu_flag adm
  INNER JOIN comorb co ON adm.hadm_id = co.hadm_id
)
SELECT 
  icu_cat,
  los_cat,
  comorb_cat,
  total,
  deaths,
  mortality_pct,
  ROUND(
    GREATEST(
      0, 
      (deaths * 1.0 / total - 1.96 * SQRT((deaths * 1.0 / total) * (1 - deaths * 1.0 / total) / total)
    )) * 100
  , 2
  ) AS ci_lower,
  ROUND(
    LEAST(
      1.0, 
      (deaths * 1.0 / total + 1.96 * SQRT((deaths * 1.0 / total) * (1 - deaths * 1.0 / total) / total)
    )) * 100
  , 2
  ) AS ci_upper
FROM (
  SELECT 
    icu_cat,
    los_cat,
    comorb_cat,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct
  FROM final_cohort
  GROUP BY icu_cat, los_cat, comorb_cat
) AS groups
ORDER BY icu_cat, los_cat, comorb_cat;