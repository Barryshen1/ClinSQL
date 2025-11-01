WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 47 AND 57
    AND a.dischtime IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
admissions_with_diagnosis AS (
  SELECT 
    fa.*
  FROM filtered_admissions fa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE d.hadm_id = fa.hadm_id
      AND dd.icd_code IN ('K85.0', 'K85.1', 'K85.2', 'K85.8', 'K85.9')
      AND dd.icd_version = 10
  )
),
admissions_with_procedures AS (
  SELECT 
    awd.hadm_id,
    awd.los_group,
    COUNT(h.hadm_id) AS num_procedures
  FROM admissions_with_diagnosis awd
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON awd.hadm_id = h.hadm_id
    AND h.chartdate BETWEEN DATE(awd.admittime) AND DATE(awd.dischtime)
    AND (h.short_description LIKE '%CT%' OR h.short_description LIKE '%MRI%')
  GROUP BY awd.hadm_id, awd.los_group
)
SELECT 
  los_group,
  COUNT(hadm_id) AS patient_count,
  AVG(num_procedures) AS mean_procedures_per_admission
FROM admissions_with_procedures
GROUP BY los_group
ORDER BY 
  CASE los_group
    WHEN '1-4 days' THEN 1
    WHEN '5-8 days' THEN 2
  END;