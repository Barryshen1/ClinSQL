WITH hf_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
),
cci_flags AS (
  SELECT
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '410%') OR 
           (icd_version = 10 AND icd_code LIKE 'I21%') 
      THEN 1 ELSE 0 END) AS MI,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '428%') OR 
           (icd_version = 10 AND icd_code LIKE 'I50%') 
      THEN 1 ELSE 0 END) AS CHF,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '430%') OR 
           (icd_version = 10 AND icd_code LIKE 'I60%') 
      THEN 1 ELSE 0 END) AS CVD
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cci_score AS (
  SELECT
    hadm_id,
    (MI*1) + (CHF*1) + (CVD*1) AS cci_score
  FROM cci_flags
),
cohort_with_cci AS (
  SELECT
    c.*,
    cs.cci_score,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    CASE 
      WHEN cs.cci_score <= 3 THEN '<=3'
      WHEN cs.cci_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS cci_cat
  FROM hf_cohort c
  LEFT JOIN cci_score cs USING (hadm_id)
),
mortality_stats AS (
  SELECT
    los_cat,
    cci_cat,
    COUNT(*) AS admissions,
    SUM(hospital_expire_flag) AS deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_pct
  FROM cohort_with_cci
  GROUP BY los_cat, cci_cat
)
SELECT * 
FROM mortality_stats
ORDER BY los_cat, cci_cat;


-- Query 2: Discharge destination distribution
WITH hf_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
),
cci_flags AS (
  SELECT
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '410%') OR 
           (icd_version = 10 AND icd_code LIKE 'I21%') 
      THEN 1 ELSE 0 END) AS MI,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '428%') OR 
           (icd_version = 10 AND icd_code LIKE 'I50%') 
      THEN 1 ELSE 0 END) AS CHF,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '430%') OR 
           (icd_version = 10 AND icd_code LIKE 'I60%') 
      THEN 1 ELSE 0 END) AS CVD
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cci_score AS (
  SELECT
    hadm_id,
    (MI*1) + (CHF*1) + (CVD*1) AS cci_score
  FROM cci_flags
),
cohort_with_cci AS (
  SELECT
    c.*,
    cs.cci_score,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    CASE 
      WHEN cs.cci_score <= 3 THEN '<=3'
      WHEN cs.cci_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS cci_cat
  FROM hf_cohort c
  LEFT JOIN cci_score cs USING (hadm_id)
),
discharge_stats AS (
  SELECT
    CASE 
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%REHAB%' THEN 'Rehab'
      WHEN discharge_location LIKE '%SKILLED NURSING%' THEN 'SNF'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_cat,
    COUNT(*) AS discharges,
    SAFE_DIVIDE(COUNT(*), (SELECT COUNT(*) FROM cohort_with_cci)) * 100 AS pct
  FROM cohort_with_cci
  GROUP BY discharge_cat
)
SELECT * 
FROM discharge_stats
ORDER BY pct DESC;