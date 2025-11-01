WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    (EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
hf_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR 
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
base AS (
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, 
    c.hospital_expire_flag, c.los_days
  FROM cohort c
  INNER JOIN hf_admissions hf
    ON c.subject_id = hf.subject_id AND c.hadm_id = hf.hadm_id
  WHERE c.age_at_admission BETWEEN 77 AND 87
),
day1_icu_flag AS (
  SELECT 
    b.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE 
          b.subject_id = icu.subject_id AND 
          b.hadm_id = icu.hadm_id AND 
          icu.intime BETWEEN b.admittime AND 
          DATETIME_ADD(b.admittime, INTERVAL 1 DAY)
      ) THEN 'ICU'
      ELSE 'non-ICU'
    END AS day1_icu
  FROM base b
),
conditions AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code = '586' OR icd_code LIKE 'V42.0' OR icd_code LIKE 'V45.1' OR icd_code LIKE 'V56%')) OR
               (icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code = 'N19' OR icd_code LIKE 'Z49%' OR icd_code LIKE 'Z94.0' OR icd_code LIKE 'Z99.2'))
          THEN 1 ELSE 0 
        END) AS ckd_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%') OR
               (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
          THEN 1 ELSE 0 
        END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    d.*,
    COALESCE(c.ckd_flag, 0) AS ckd_flag,
    COALESCE(c.diabetes_flag, 0) AS diabetes_flag
  FROM day1_icu_flag d
  LEFT JOIN conditions c USING (hadm_id)
)
SELECT 
  day1_icu,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN los_days >= 8 THEN '>=8'
  END AS los_group,
  COUNT(*) AS n_admissions,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(SUM(ckd_flag) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(diabetes_flag) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM combined
WHERE los_days >= 1  -- Exclude same-day discharges
GROUP BY day1_icu, los_group
ORDER BY day1_icu, los_group;