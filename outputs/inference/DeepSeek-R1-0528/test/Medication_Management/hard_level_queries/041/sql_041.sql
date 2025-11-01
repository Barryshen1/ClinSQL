WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

med_complexity AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT em.medication) AS med_complexity
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON c.hadm_id = em.hadm_id
    AND em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),

readmission_flags AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN hospital_expire_flag = 1 THEN NULL  -- Exclude deceased
      WHEN LEAD(admittime) OVER (
              PARTITION BY subject_id ORDER BY admittime
            ) <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmit_30_flag
  FROM cohort
),

combined_data AS (
  SELECT 
    c.hadm_id,
    mc.med_complexity,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag,
    rf.readmit_30_flag,
    NTILE(5) OVER (ORDER BY mc.med_complexity) AS quintile
  FROM cohort c
  LEFT JOIN med_complexity mc ON c.hadm_id = mc.hadm_id
  LEFT JOIN readmission_flags rf ON c.hadm_id = rf.hadm_id
)

SELECT 
  quintile,
  COUNT(hadm_id) AS patient_count,
  MIN(med_complexity) AS min_score,
  MAX(med_complexity) AS max_score,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag), 4) AS in_hospital_mortality,
  ROUND(AVG(readmit_30_flag), 4) AS readmission_rate
FROM combined_data
GROUP BY quintile
ORDER BY quintile;