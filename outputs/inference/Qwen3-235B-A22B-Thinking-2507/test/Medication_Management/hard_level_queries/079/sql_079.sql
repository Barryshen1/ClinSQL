WITH hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
    OR (icd_version = 9 AND icd_code IN ('430', '431', '432'))
),
base_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN hemorrhagic_stroke_admissions hsa
    ON a.hadm_id = hsa.hadm_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),
med_complexity AS (
  SELECT 
    bp.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM base_population bp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON bp.hadm_id = pr.hadm_id
    AND pr.starttime >= bp.admittime
    AND pr.starttime < DATETIME_ADD(bp.admittime, INTERVAL 7 DAY)
    AND pr.drug IS NOT NULL
  GROUP BY bp.hadm_id
),
with_quintile AS (
  SELECT 
    bp.*,
    mc.med_count,
    NTILE(5) OVER (ORDER BY mc.med_count) AS quintile
  FROM base_population bp
  INNER JOIN med_complexity mc
    ON bp.hadm_id = mc.hadm_id
),
with_readmission AS (
  SELECT 
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM with_quintile
),
final_cohort AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) 
        THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM with_readmission
)
SELECT 
  quintile,
  AVG((UNIX_SECONDS(CAST(dischtime AS TIMESTAMP)) - UNIX_SECONDS(CAST(admittime AS TIMESTAMP))) / 86400.0) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmitted_30d) AS readmission_rate
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;