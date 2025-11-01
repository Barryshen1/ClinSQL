WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 48 AND 58  -- Pre-filter approximate age
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) = 1
),
cabg_admissions AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag,
    fa.age_at_adm
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.hadm_id = pi.hadm_id
  WHERE (pi.icd_version = 9 AND pi.icd_code LIKE '36.1%')
     OR (pi.icd_version = 10 
         AND (pi.icd_code LIKE '021%' 
              OR pi.icd_code LIKE '022%' 
              OR pi.icd_code LIKE '023%' 
              OR pi.icd_code LIKE '024%'))
)
SELECT 
  COUNT(*) AS total_cabg_admissions,
  SUM(CAST(hospital_expire_flag AS INT64)) AS num_deaths,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM cabg_admissions;