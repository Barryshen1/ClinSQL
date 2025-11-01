WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
),
cabc_cohort AS (
  SELECT 
    fa.*,
    ROW_NUMBER() OVER (PARTITION BY fa.subject_id ORDER BY fa.admittime) AS rn
  FROM 
    first_admissions fa
  WHERE 
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON di.subject_id = pi.subject_id AND di.hadm_id = pi.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` pd
      ON pi.icd_code = pd.icd_code AND pi.icd_version = pd.icd_version
      WHERE 
        di.subject_id = fa.subject_id
        AND di.hadm_id = fa.hadm_id
        AND di.icd_version = 10
        AND di.seq_num = 1
        AND di.icd_code LIKE 'I2%'
        AND LOWER(dd.long_title) LIKE '%bypass%'
        AND pi.icd_version = 10
        AND pi.icd_code LIKE '0XJ%'
        AND LOWER(pd.long_title) LIKE '%bypass%'
    )
),
mortality_stats AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS total_cabc_admissions,
    COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS deaths
  FROM 
    cabc_cohort
  WHERE 
    rn = 1
),
mortality_rate AS (
  SELECT 
    total_cabc_admissions,
    deaths,
    SAFE_DIVIDE(deaths, total_cabc_admissions) * 100 AS mortality_rate_percent
  FROM 
    mortality_stats
)
SELECT 
  total_cabc_admissions,
  deaths,
  mortality_rate_percent
FROM 
  mortality_rate;