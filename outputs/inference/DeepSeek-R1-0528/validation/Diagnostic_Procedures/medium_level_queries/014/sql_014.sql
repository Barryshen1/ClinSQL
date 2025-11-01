WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN d_icd.seq_num = 1 THEN 1 ELSE 0 END) AS primary_acs,
    MAX(CASE WHEN d_icd.seq_num > 1 THEN 1 ELSE 0 END) AS secondary_acs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
      (d_icd.icd_version = 9 AND d_icd.icd_code IN ('410%', '411.1', '411.81'))
      OR
      (d_icd.icd_version = 10 AND d_icd.icd_code IN ('I20.0%', 'I21%', 'I22%', 'I23%', 'I24.0%', 'I24.8%', 'I24.9%'))
    )
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING los_days BETWEEN 1 AND 7
),

cohort_with_type AS (
  SELECT 
    hadm_id,
    subject_id,
    los_days,
    CASE 
      WHEN primary_acs = 1 THEN 'Primary'
      WHEN secondary_acs = 1 THEN 'Secondary'
    END AS acs_diag_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM cohort
  WHERE primary_acs = 1 OR secondary_acs = 1
),

ultrasound_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS ultrasound_count
  FROM (
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%ultrasound%'
      AND p.hadm_id IN (SELECT hadm_id FROM cohort)

    UNION ALL

    SELECT h.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
    WHERE LOWER(d.long_description) LIKE '%ultrasound%'
      AND h.hadm_id IN (SELECT hadm_id FROM cohort)
  )
  GROUP BY hadm_id
)

SELECT 
  c.los_group,
  c.acs_diag_type,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(u.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(u.ultrasound_count, 0)) AS max_ultrasounds
FROM cohort_with_type c
LEFT JOIN ultrasound_counts u
  ON c.hadm_id = u.hadm_id
GROUP BY c.los_group, c.acs_diag_type
ORDER BY c.los_group, c.acs_diag_type;