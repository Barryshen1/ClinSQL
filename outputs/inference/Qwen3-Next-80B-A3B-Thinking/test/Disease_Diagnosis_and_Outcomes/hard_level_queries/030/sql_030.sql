WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.dod,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE 'K22.1%' 
             OR d.icd_code LIKE 'K22.2%' 
             OR d.icd_code LIKE 'K22.3%' 
             OR d.icd_code LIKE 'K25%' 
             OR d.icd_code LIKE 'K26%' 
             OR d.icd_code LIKE 'K27%' 
             OR d.icd_code LIKE 'K28%')
    )
),
diagnosis_counts AS (
  SELECT
    c.hadm_id,
    COUNT(d.icd_code) AS diagnosis_count,
    MAX(CASE WHEN d.icd_code LIKE 'R57%' 
              OR d.icd_code LIKE 'A41%' 
              OR d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS major_complication
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),
scored_cohort AS (
  SELECT
    c.hadm_id,
    dc.diagnosis_count,
    dc.major_complication,
    dc.diagnosis_count + 20 * dc.major_complication AS score,
    CASE 
      WHEN c.dod IS NOT NULL AND c.dod <= DATE_ADD(c.admittime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    CASE 
      WHEN c.hospital_expire_flag = 0 THEN c.los 
      ELSE NULL 
    END AS los_survivors
  FROM cohort c
  JOIN diagnosis_counts dc ON c.hadm_id = dc.hadm_id
),
quintiles AS (
  SELECT
    NTILE(5) OVER (ORDER BY score) AS quintile,
    score,
    thirty_day_mortality,
    major_complication,
    los_survivors
  FROM scored_cohort
)
SELECT
  quintile,
  COUNT(*) AS n,
  AVG(score) AS mean_score,
  AVG(thirty_day_mortality) * 100 AS thirty_day_mortality_percent,
  AVG(major_complication) * 100 AS major_complication_percent,
  MEDIAN(los_survivors) AS median_los_survivors
FROM quintiles
GROUP BY quintile
ORDER BY quintile;