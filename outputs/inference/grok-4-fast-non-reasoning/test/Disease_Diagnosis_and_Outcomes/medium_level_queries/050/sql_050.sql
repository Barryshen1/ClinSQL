WITH base_cohort AS (
  -- Join patients and admissions, filter men 75-85, calculate LOS
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    SAFE.DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN SAFE.DATE_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime > a.admittime  -- Exclude zero/negative LOS
),

sepsis_cohort AS (
  -- Filter for sepsis (exclude septic shock)
  SELECT 
    bc.*,
    CASE 
      WHEN di.icd_version = 'ICD-9' AND REGEXP_CONTAINS(di.icd_code, r'^038\.|785\.52|995\.9[12]') THEN 1
      WHEN di.icd_version = 'ICD-10' AND REGEXP_CONTAINS(di.icd_code, r'^A4[01]\.') THEN 1
      ELSE 0 
    END AS has_sepsis,
    CASE 
      WHEN di.icd_version = 'ICD-9' AND di.icd_code IN ('785.52') THEN 1  -- Simplified; could refine
      WHEN di.icd_version = 'ICD-10' AND di.icd_code = 'R65.21' THEN 1
      ELSE 0 
    END AS has_septic_shock
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON bc.hadm_id = di.hadm_id
  GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag, 
           bc.gender, bc.anchor_age, bc.los_days, bc.los_group  -- Aggregate diagnoses per admission
  HAVING SUM(has_sepsis) > 0 AND SUM(has_septic_shock) = 0  -- Sepsis yes, shock no
),

comorbidities AS (
  -- Flag comorbidities using EXISTS (presence in diagnoses)
  SELECT 
    sc.*,
    MAX(CASE 
      WHEN d.icd_version = 'ICD-9' AND REGEXP_CONTAINS(d.icd_code, r'^585\.')
        OR d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^N18\.') THEN 1 ELSE 0 
    END) AS has_ckd,
    MAX(CASE 
      WHEN d.icd_version = 'ICD-9' AND REGEXP_CONTAINS(d.icd_code, r'^(249\.|250\.)')
        OR d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^(E1[0-3]\.|O24\.)') THEN 1 ELSE 0 
    END) AS has_diabetes,
    MAX(CASE 
      WHEN d.icd_version = 'ICD-9' AND d.icd_code = '427.31'
        OR d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^I48\.') THEN 1 ELSE 0 
    END) AS has_afib,
    MAX(CASE 
      WHEN d.icd_version = 'ICD-9' AND REGEXP_CONTAINS(d.icd_code, r'^40[1-5]\.')
        OR d.icd_version = 'ICD-10' AND REGEXP_CONTAINS(d.icd_code, r'^I[1-2][0-6]\.') THEN 1 ELSE 0 
    END) AS has_hypertension
  FROM sepsis_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON sc.hadm_id = d.hadm_id
  GROUP BY 
    sc.subject_id, sc.hadm_id, sc.admittime, sc.dischtime, sc.hospital_expire_flag, 
    sc.gender, sc.anchor_age, sc.los_days, sc.los_group
)

-- Aggregate by strata: mortality %
SELECT 
  los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  COUNT(DISTINCT hadm_id) AS n_patients,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(DISTINCT hadm_id), 2) AS mortality_pct
FROM comorbidities
GROUP BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension
ORDER BY los_group, has_ckd, has_diabetes, has_afib, has_hypertension;