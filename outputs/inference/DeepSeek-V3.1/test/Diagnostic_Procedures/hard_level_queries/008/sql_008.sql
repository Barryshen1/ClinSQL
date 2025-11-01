WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON ie.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON ie.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '530.7%') OR
      (d.icd_version = 9 AND d.icd_code = '530.82') OR
      (d.icd_version = 10 AND d.icd_code IN ('K22.6','K22.8','K25.0','K25.4','K26.0','K26.4','K27.0','K27.4','K28.0','K28.4','K29.0','K92.0','K92.1','K92.2'))
    )
),
procedures_first_24h AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CONCAT(p.icd_code, p.icd_version)) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
    ON c.hadm_id = p.hadm_id
    AND DATE_DIFF(DATE(p.chartdate), DATE(c.intime), DAY) BETWEEN 0 AND 1
  GROUP BY c.hadm_id
),
quintiles AS (
  SELECT
    hadm_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedures_first_24h
)
SELECT
  q.quintile,
  COUNT(*) AS num_patients,
  AVG(q.procedure_count) AS avg_procedures,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los_days,
  100.0 * SUM(a.hospital_expire_flag) / COUNT(*) AS mortality_percent
FROM quintiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON q.hadm_id = a.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;