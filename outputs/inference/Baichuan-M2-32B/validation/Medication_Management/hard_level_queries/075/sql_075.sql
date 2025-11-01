WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.`admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.`patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.`diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 58 AND 68
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J44.%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
medication_complexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.formulary_drug_cd) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.`prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
next_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime, hadm_id) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.`admissions`
),
readmission_flags AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.dischtime,
    CASE 
      WHEN na.next_admittime IS NOT NULL 
        AND na.next_admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM cohort c
  LEFT JOIN next_admissions na
    ON c.subject_id = na.subject_id AND c.hadm_id = na.hadm_id
),
combined AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    COALESCE(mc.complexity_score, 0) AS complexity_score,
    r.readmitted,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 86400.0 AS los_days
  FROM cohort c
  INNER JOIN medication_complexity mc ON c.hadm_id = mc.hadm_id
  INNER JOIN readmission_flags r ON c.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined
)
SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  ROUND(AVG(complexity_score), 2) AS mean_complexity,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(readmitted) * 100, 2) AS readmission_30d_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;