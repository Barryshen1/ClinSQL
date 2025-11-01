WITH eligible_patients AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E1%' AND d.icd_code NOT LIKE 'E15%' AND d.icd_code NOT LIKE 'E16%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
      WHERE 
        h.subject_id = p.subject_id 
        AND h.hadm_id = a.hadm_id
        AND (
          (h.icd_version = 9 AND h.icd_code LIKE '428%')
          OR (h.icd_version = 10 AND h.icd_code LIKE 'I50%')
        )
    )
),
prescriptions_with_flags AS (
  SELECT
    e.subject_id,
    p.starttime,
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS insulin_flag,
    CASE WHEN LOWER(p.route) = 'oral' THEN 1 ELSE 0 END AS oral_flag,
    CASE WHEN p.starttime BETWEEN e.admittime AND e.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END AS in_first12,
    CASE WHEN p.starttime BETWEEN e.dischtime - INTERVAL '48' HOUR AND e.dischtime THEN 1 ELSE 0 END AS in_final48
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON e.hadm_id = p.hadm_id
),
patient_flags AS (
  SELECT
    subject_id,
    MAX(CASE WHEN in_first12 = 1 AND insulin_flag = 1 THEN 1 ELSE 0 END) AS first12_insulin,
    MAX(CASE WHEN in_first12 = 1 AND oral_flag = 1 THEN 1 ELSE 0 END) AS first12_oral,
    MAX(CASE WHEN in_final48 = 1 AND insulin_flag = 1 THEN 1 ELSE 0 END) AS final48_insulin,
    MAX(CASE WHEN in_final48 = 1 AND oral_flag = 1 THEN 1 ELSE 0 END) AS final48_oral
  FROM prescriptions_with_flags
  GROUP BY subject_id
)
SELECT
  AVG(first12_insulin) * 100 AS insulin_first12_pct,
  AVG(first12_oral) * 100 AS oral_first12_pct,
  AVG(final48_insulin) * 100 AS insulin_final48_pct,
  AVG(final48_oral) * 100 AS oral_final48_pct,
  (AVG(final48_insulin) - AVG(first12_insulin)) * 100 AS insulin_net_change,
  (AVG(final48_oral) - AVG(first12_oral)) * 100 AS oral_net_change
FROM patient_flags;