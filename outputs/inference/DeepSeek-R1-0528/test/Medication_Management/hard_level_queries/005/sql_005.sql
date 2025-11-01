WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code 
        AND diag.icd_version = d.icd_version
      WHERE LOWER(d.long_title) LIKE '%hepatic failure%'
    )
),

cohort_age_filtered AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM cohort
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 43 AND 53
),

medications AS (
  SELECT 
    cf.hadm_id,  -- Explicitly use cf.hadm_id to avoid ambiguity
    COUNT(DISTINCT em.medication) AS med_complexity_score
  FROM cohort_age_filtered cf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON cf.hadm_id = em.hadm_id
  WHERE em.charttime BETWEEN cf.admittime AND DATETIME_ADD(cf.admittime, INTERVAL 72 HOUR)
  GROUP BY cf.hadm_id
),

cohort_with_score AS (
  SELECT 
    cf.subject_id,
    cf.hadm_id,
    cf.admittime,
    cf.dischtime,
    cf.hospital_expire_flag,
    cf.age_at_admission,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM cohort_age_filtered cf
  LEFT JOIN medications m
    ON cf.hadm_id = m.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM cohort_with_score
),

readmissions AS (
  SELECT 
    q.hadm_id,
    MIN(a.admittime) AS next_admittime
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON q.subject_id = a.subject_id
    AND a.admittime > q.dischtime
  WHERE q.hospital_expire_flag = 0  -- Only survivors can be readmitted
  GROUP BY q.hadm_id  -- Qualify with q.hadm_id
),

cohort_outcomes AS (
  SELECT 
    q.subject_id,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    q.hospital_expire_flag,
    q.age_at_admission,
    q.med_complexity_score,
    q.quintile,
    DATETIME_DIFF(q.dischtime, q.admittime, DAY) AS los_days,
    CASE 
      WHEN q.hospital_expire_flag = 1 THEN NULL  -- Exclude deceased
      WHEN DATETIME_DIFF(r.next_admittime, q.dischtime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS readmission_30d
  FROM quintiles q
  LEFT JOIN readmissions r
    ON q.hadm_id = r.hadm_id
)

SELECT 
  quintile,
  COUNT(*) AS n,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  ROUND(AVG(med_complexity_score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_pct,
  ROUND(100 * AVG(readmission_30d), 2) AS readmission_30d_pct  -- NULLs (deceased) ignored in AVG
FROM cohort_outcomes
GROUP BY quintile
ORDER BY quintile;