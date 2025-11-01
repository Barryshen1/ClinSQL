WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS admission_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
          OR (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430', '431', '432'))
        )
    )
),
with_metrics AS (
  SELECT 
    c.*,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    COUNT(d.icd_code) AS num_diagnoses,
    MAX(CASE 
      WHEN (
        (d.icd_version = 10 AND (
          SUBSTR(d.icd_code, 1, 3) IN ('I21', 'I46', 'I47', 'I48', 'I49', 'I50') 
          OR d.icd_code LIKE 'R57.0%'
        ))
        OR (d.icd_version = 9 AND (
          SUBSTR(d.icd_code, 1, 3) IN ('410', '427', '428', '785')
        ))
      ) THEN 1 
      ELSE 0 
    END) AS has_cardiac,
    MAX(CASE 
      WHEN (
        (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('G40', 'G41', 'G91', 'G93'))
        OR (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('345', '331', '348'))
      ) THEN 1 
      ELSE 0 
    END) AS has_neuro
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, 
    c.gender, c.anchor_age, c.anchor_year, c.admission_age
),
with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY num_diagnoses) AS quartile
  FROM with_metrics
)
SELECT 
  quartile,
  COUNT(*) AS patient_counts,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS in_hospital_mortality_rate,
  SAFE_DIVIDE(SUM(has_cardiac), COUNT(*)) * 100 AS cardiac_complication_rate,
  SAFE_DIVIDE(SUM(has_neuro), COUNT(*)) * 100 AS neurologic_complication_rate,
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, los, NULL), 3)[OFFSET(1)] AS median_los_survivors
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;