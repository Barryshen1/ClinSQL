WITH sepsis_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
  GROUP BY hadm_id
),
shock_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code = 'R6521'
  GROUP BY hadm_id
),
sepsis_no_shock AS (
  SELECT hadm_id
  FROM sepsis_admissions
  WHERE hadm_id NOT IN (SELECT hadm_id FROM shock_admissions)
),
demographic AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
sepsis_demo AS (
  SELECT d.*
  FROM demographic d
  INNER JOIN sepsis_no_shock s
    ON d.hadm_id = s.hadm_id
  WHERE d.age_at_admission BETWEEN 49 AND 59
),
with_icu_flag AS (
  SELECT 
    s.*,
    -- ICU day1 flag: 1 if there is an ICU stay starting within 24 hours of admission
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = s.hadm_id 
        AND i.intime < s.admittime + INTERVAL '1' DAY
    ) THEN 1 ELSE 0 END AS icu_day1
  FROM sepsis_demo s
),
with_comorbidities AS (
  SELECT 
    w.*,
    -- CKD: any diagnosis code starting with 'N18' (ICD-10) in this admission
    MAX(CASE WHEN d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS ckd_present,
    -- Diabetes: E08, E09, E10, E11, E13, E14
    MAX(CASE WHEN d_icd.icd_version = 10 
             AND (d_icd.icd_code LIKE 'E08%' 
                  OR d_icd.icd_code LIKE 'E09%' 
                  OR d_icd.icd_code LIKE 'E10%' 
                  OR d_icd.icd_code LIKE 'E11%' 
                  OR d_icd.icd_code LIKE 'E13%' 
                  OR d_icd.icd_code LIKE 'E14%') 
             THEN 1 ELSE 0 END) AS diabetes_present
  FROM with_icu_flag w
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON w.hadm_id = d_icd.hadm_id
  GROUP BY w.subject_id, w.gender, w.anchor_age, w.anchor_year, w.hadm_id, 
           w.admittime, w.dischtime, w.hospital_expire_flag, w.age_at_admission, 
           w.hospital_los, w.icu_day1
)
SELECT
  CASE WHEN hospital_los <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  CASE WHEN icu_day1 = 1 THEN 'ICU' ELSE 'non-ICU' END AS icu_group,
  COUNT(*) AS N,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct,
  ROUND(SUM(ckd_present) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(diabetes_present) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM with_comorbidities
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;