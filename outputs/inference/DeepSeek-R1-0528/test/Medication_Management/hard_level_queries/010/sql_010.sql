WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    -- Approximate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code BETWEEN '430' AND '432') 
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I6[0-2]%')
        )
    )
    -- Replace HAVING with WHERE and repeat age calculation
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 61 AND 71
),

medications AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS medication_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

cohort_with_quintile AS (
  SELECT 
    c.*,
    m.medication_count,
    NTILE(5) OVER (ORDER BY m.medication_count) AS quintile
  FROM cohort c
  INNER JOIN medications m
    ON c.hadm_id = m.hadm_id AND c.subject_id = m.subject_id
),

readmission_flags AS (
  SELECT 
    c.*,
    -- LOS in days
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    -- Readmission flag (only for survivors)
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN NULL  -- Exclude in-hospital deaths
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a 
        WHERE 
          a.subject_id = c.subject_id 
          AND a.hadm_id <> c.hadm_id 
          AND a.admittime > c.dischtime 
          AND a.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmission_flag
  FROM cohort_with_quintile c
)

SELECT 
  quintile,
  COUNT(hadm_id) AS n_patients,
  AVG(medication_count) AS mean_complexity_score,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate,
  -- Readmission rate: % of readmissions among survivors
  SAFE_DIVIDE(
    SUM(CASE WHEN readmission_flag = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)
  ) * 100 AS readmission_rate
FROM readmission_flags
GROUP BY quintile
ORDER BY quintile;