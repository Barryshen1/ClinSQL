WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admission_type,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Categorize admission type
    CASE WHEN adm.admission_type = 'EMERGENCY' THEN 'emergent' ELSE 'non-emergent' END AS admission_cat,
    -- Categorize LOS
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
      ELSE 'other' 
    END AS los_group,
    -- Time to death in days (for those who died)
    CASE WHEN adm.hospital_expire_flag = 1 THEN DATE_DIFF(adm.deathtime, adm.admittime, DAY) ELSE NULL END AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND adm.hadm_id IN (
      -- Admissions with AMI
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
    )
    AND adm.hadm_id NOT IN (
      -- Exclude admissions with initial shock or respiratory failure (seq_num <= 5)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'R57%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '7855%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J96%')
          OR (diag.icd_version = 9 AND diag.icd_code = '51881')
        )
        AND diag.seq_num <= 5
    )
),

median_ttd AS (
  SELECT 
    admission_cat,
    los_group,
    APPROX_QUANTILE(time_to_death_days, 0.5) AS median_time_to_death_days
  FROM cohort
  WHERE los_group != 'other' AND hospital_expire_flag = 1
  GROUP BY admission_cat, los_group
)

SELECT 
  c.admission_cat,
  c.los_group,
  COUNT(*) AS n_admissions,
  SUM(c.hospital_expire_flag) AS n_deaths,
  ROUND(100 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  m.median_time_to_death_days
FROM cohort c
LEFT JOIN median_ttd m
  ON c.admission_cat = m.admission_cat AND c.los_group = m.los_group
WHERE c.los_group != 'other'
GROUP BY c.admission_cat, c.los_group, m.median_time_to_death_days
ORDER BY c.admission_cat, c.los_group;